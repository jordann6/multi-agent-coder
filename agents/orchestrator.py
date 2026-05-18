import json
import os
from typing import Any

import anthropic
import boto3

from tools.registry import ORCHESTRATOR_TOOLS

MAX_ITERATIONS = 5

SYSTEM_PROMPT = """You are an Orchestrator agent. Your job is to analyze incoming tasks and route them to the correct specialist.

Available specialists:
- Coder: handles write_code, explain_code, and debug_code tasks

Routing rules:
1. Determine whether the task involves writing, explaining, or debugging code.
2. Identify the programming language if mentioned; default to python if not specified.
3. Route the full task to the Coder specialist using invoke_coder.
4. Return the specialist result plus your routing reasoning.

Final response must be valid JSON with no markdown or backticks:
{
  "task": "original task text",
  "specialist": "coder",
  "result": <specialist result object>,
  "orchestrator_reasoning": "one sentence on why you routed this way"
}"""


def get_secret(secret_arn: str) -> str:
    client = boto3.client("secretsmanager", region_name=os.environ.get("AWS_REGION", "us-east-1"))
    response = client.get_secret_value(SecretId=secret_arn)
    return response["SecretString"]


def invoke_coder(task: str) -> dict[str, Any]:
    lambda_client = boto3.client("lambda", region_name=os.environ.get("AWS_REGION", "us-east-1"))
    response = lambda_client.invoke(
        FunctionName=os.environ["CODER_LAMBDA_ARN"],
        InvocationType="RequestResponse",
        Payload=json.dumps({"task": task}).encode(),
    )
    payload = json.loads(response["Payload"].read())
    if "errorMessage" in payload:
        return {"error": payload["errorMessage"]}
    return payload


def run_orchestrator(task: str) -> dict[str, Any]:
    api_key = get_secret(os.environ["ANTHROPIC_SECRET_ARN"])
    client = anthropic.Anthropic(api_key=api_key)

    messages: list[dict[str, Any]] = [{"role": "user", "content": task}]

    for _ in range(MAX_ITERATIONS):
        response = client.messages.create(
            model="claude-sonnet-4-20250514",
            max_tokens=2048,
            system=SYSTEM_PROMPT,
            tools=ORCHESTRATOR_TOOLS,
            messages=messages,
        )

        messages.append({"role": "assistant", "content": response.content})

        if response.stop_reason == "end_turn":
            for block in response.content:
                if block.type == "text":
                    try:
                        return json.loads(block.text)
                    except json.JSONDecodeError:
                        return {
                            "task": task,
                            "specialist": "unknown",
                            "result": {"explanation": block.text},
                            "orchestrator_reasoning": "Returned unstructured response",
                        }
            break

        if response.stop_reason == "tool_use":
            tool_results = []
            for block in response.content:
                if block.type == "tool_use":
                    if block.name == "invoke_coder":
                        output = invoke_coder(**block.input)
                    else:
                        output = {"error": f"Unknown tool: {block.name}"}
                    tool_results.append(
                        {
                            "type": "tool_result",
                            "tool_use_id": block.id,
                            "content": json.dumps(output),
                        }
                    )
            messages.append({"role": "user", "content": tool_results})

    return {
        "task": task,
        "specialist": "unknown",
        "result": {},
        "orchestrator_reasoning": "Max iterations reached without a final response",
    }
