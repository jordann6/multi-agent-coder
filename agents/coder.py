import json
import logging
import os
from datetime import datetime, timezone
from typing import Any

import anthropic
import boto3

from tools.code_tools import TOOL_DISPATCH
from tools.registry import CODER_TOOLS

logger = logging.getLogger()

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

_dynamodb = boto3.resource("dynamodb", region_name=os.environ.get("AWS_REGION", "us-east-1"))
_secrets_client = boto3.client("secretsmanager", region_name=os.environ.get("AWS_REGION", "us-east-1"))
_cached_api_key: str | None = None


def _get_api_key() -> str:
    global _cached_api_key
    if _cached_api_key is None:
        _cached_api_key = _secrets_client.get_secret_value(
            SecretId=os.environ["ANTHROPIC_SECRET_ARN"]
        )["SecretString"]
    return _cached_api_key


def _dynamo_table():
    return _dynamodb.Table(os.environ["JOBS_TABLE"])


def _store_result(job_id: str, result: dict[str, Any]) -> None:
    _dynamo_table().update_item(
        Key={"job_id": job_id},
        UpdateExpression="SET #s = :s, #r = :r, completed_at = :c",
        ExpressionAttributeNames={"#s": "status", "#r": "result"},
        ExpressionAttributeValues={
            ":s": "complete",
            ":r": result,
            ":c": datetime.now(timezone.utc).isoformat(),
        },
    )


def _store_error(job_id: str, error: str) -> None:
    _dynamo_table().update_item(
        Key={"job_id": job_id},
        UpdateExpression="SET #s = :s, #e = :e, completed_at = :c",
        ExpressionAttributeNames={"#s": "status", "#e": "error"},
        ExpressionAttributeValues={
            ":s": "error",
            ":e": error,
            ":c": datetime.now(timezone.utc).isoformat(),
        },
    )


def run_coder_agent(task: str, job_id: str | None = None) -> dict[str, Any]:
    client = anthropic.Anthropic(api_key=_get_api_key())
    model = os.environ.get("MODEL_ID", "claude-sonnet-4-6")

    messages: list[dict[str, Any]] = [{"role": "user", "content": task}]
    result: dict[str, Any] = {}

    try:
        for _ in range(MAX_ITERATIONS):
            response = client.messages.create(
                model=model,
                max_tokens=4096,
                system=[
                    {
                        "type": "text",
                        "text": SYSTEM_PROMPT,
                        "cache_control": {"type": "ephemeral"},
                    }
                ],
                tools=CODER_TOOLS,
                messages=messages,
            )

            messages.append({"role": "assistant", "content": response.content})

            if response.stop_reason == "end_turn":
                for block in response.content:
                    if block.type == "text":
                        try:
                            result = json.loads(block.text)
                        except json.JSONDecodeError:
                            result = {
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
                        output = tool_fn(**block.input) if tool_fn else {"error": f"Unknown tool: {block.name}"}
                        tool_results.append(
                            {
                                "type": "tool_result",
                                "tool_use_id": block.id,
                                "content": json.dumps(output),
                            }
                        )
                messages.append({"role": "user", "content": tool_results})

        if not result:
            if job_id:
                _store_error(job_id, "Agent reached maximum iterations without producing a final answer")
            return {"task_type": "unknown", "result": {}, "summary": "Max iterations reached"}

        if job_id:
            _store_result(job_id, result)

    except Exception as e:
        logger.exception("Coder agent failed for job %s", job_id)
        if job_id:
            _store_error(job_id, "Internal agent error")
        raise

    return result
