import json
import os
import uuid
from datetime import datetime, timezone
from typing import Any

import boto3

_dynamodb = boto3.resource("dynamodb", region_name=os.environ.get("AWS_REGION", "us-east-1"))
_lambda_client = boto3.client("lambda", region_name=os.environ.get("AWS_REGION", "us-east-1"))


def _dynamo_table():
    return _dynamodb.Table(os.environ["JOBS_TABLE"])


def _create_job(task: str) -> str:
    job_id = str(uuid.uuid4())
    _dynamo_table().put_item(
        Item={
            "job_id": job_id,
            "status": "pending",
            "task": task,
            "created_at": datetime.now(timezone.utc).isoformat(),
            "expires_at": int(datetime.now(timezone.utc).timestamp()) + 86400,
        }
    )
    return job_id


def _dispatch_coder(job_id: str, task: str) -> None:
    _lambda_client.invoke(
        FunctionName=os.environ["CODER_LAMBDA_ARN"],
        InvocationType="Event",
        Payload=json.dumps({"job_id": job_id, "task": task}).encode(),
    )


def run_orchestrator(task: str) -> dict[str, Any]:
    job_id = _create_job(task)
    _dispatch_coder(job_id, task)
    return {
        "job_id": job_id,
        "status": "pending",
        "message": f"Job accepted. Poll GET /status/{job_id} for results.",
    }
