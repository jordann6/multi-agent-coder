import json
import os
from typing import Any

import anthropic
import boto3

from tools.code_tools import TOOL_DISPATCH
from tools.registry import CODER_TOOLS

MAX_ITERATIONS = 10

SYSTEM_PROMPT = """You are a Coder specialist agent. You receive coding tasks and use your tools to produce high-quality results.

Tool usage rules:
- For write_code tasks: call write_code to get a scaffold and hints, then produce complete working code based on them.
- For explain_code tasks: call explain_code to get structural metadata, then write a clear plain-language explanation.
- For debug_code tasks: call debug_code to get diagnostic information, then explain the bug and provide a corrected version.

Always return a final structured JSON response with no markdown or backticks:
{
  "task_type": "write_code" | "explain_code" | "debug_code",
  "language": "...",
  "result": {
    "code": "...",
    "explanation": "...",
    "fixed_code": "..."
  },
  "summary": "one sentence describing what was done"
}

Include only the fields relevant to the task type. Return only valid JSON."""


def get_secret(secret_arn: str) -> str:
    client = boto3.client("secretsmanager", region_name=os.environ.get("AWS_REGION", "us-east-1"))
    response = client.get_secret_value(SecretId=secret_arn)
    return response["SecretString"]


def run_coder_agent(task: str) -> dict[str, Any]:
    api_key = get_secret(os.environ["ANTHROPIC_SECRET_ARN"])
    client = anthropic.Anthropic(api_key=api_key)

    messages: list[dict[str, Any]] = [{"role": "user", "content": task}]

    for _ in range(MAX_ITERATIONS):
        response = client.messages.create(
            model="claude-sonnet-4-20250514",
            max_tokens=4096,
            system=SYSTEM_PROMPT,
            tools=CODER_TOOLS,
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
                            "task_type": "unknown",
                            "result": {"explanation": block.text},
                            "summary": "Completed without structured output",
                        }
            break

        if response.stop_reason == "tool_use":
            tool_results = []
            for block in response.content:
                if block.type == "tool_use":
                    tool_fn = TOOL_DISPATCH.get(block.name)
                    if tool_fn:
                        output = tool_fn(**block.input)
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
        "task_type": "unknown",
        "result": {},
        "summary": "Max iterations reached without a final response",
    }
