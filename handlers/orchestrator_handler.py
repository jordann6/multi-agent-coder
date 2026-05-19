import json
import logging

from agents.orchestrator import run_orchestrator

logger = logging.getLogger()

MAX_TASK_LEN = 10_000


def handler(event: dict, context: object) -> dict:
    try:
        body = json.loads(event.get("body") or "{}")
        task = (body.get("task") or "").strip()

        if not task:
            return {
                "statusCode": 400,
                "headers": {"Content-Type": "application/json"},
                "body": json.dumps({"error": "task field is required"}),
            }

        if len(task) > MAX_TASK_LEN:
            return {
                "statusCode": 400,
                "headers": {"Content-Type": "application/json"},
                "body": json.dumps({"error": f"task exceeds maximum length of {MAX_TASK_LEN} characters"}),
            }

        result = run_orchestrator(task)

        return {
            "statusCode": 202,
            "headers": {"Content-Type": "application/json"},
            "body": json.dumps(result),
        }

    except Exception:
        logger.exception("Orchestrator handler failed")
        return {
            "statusCode": 500,
            "headers": {"Content-Type": "application/json"},
            "body": json.dumps({"error": "internal server error"}),
        }
