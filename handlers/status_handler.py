import json
import logging
import os
import uuid
from decimal import Decimal

import boto3

logger = logging.getLogger()

_dynamodb = boto3.resource("dynamodb", region_name=os.environ.get("AWS_REGION", "us-east-1"))


class _DecimalEncoder(json.JSONEncoder):
    def default(self, obj):
        if isinstance(obj, Decimal):
            return int(obj) if obj % 1 == 0 else float(obj)
        return super().default(obj)


def handler(event: dict, context: object) -> dict:
    try:
        job_id = (event.get("pathParameters") or {}).get("job_id", "").strip()

        if not job_id:
            return {
                "statusCode": 400,
                "headers": {"Content-Type": "application/json"},
                "body": json.dumps({"error": "job_id is required"}),
            }

        try:
            uuid.UUID(job_id)
        except ValueError:
            return {
                "statusCode": 400,
                "headers": {"Content-Type": "application/json"},
                "body": json.dumps({"error": "invalid job_id format"}),
            }

        table = _dynamodb.Table(os.environ["JOBS_TABLE"])
        response = table.get_item(Key={"job_id": job_id})
        item = response.get("Item")

        if not item:
            return {
                "statusCode": 404,
                "headers": {"Content-Type": "application/json"},
                "body": json.dumps({"error": "Job not found"}),
            }

        return {
            "statusCode": 200,
            "headers": {"Content-Type": "application/json"},
            "body": json.dumps(item, cls=_DecimalEncoder),
        }

    except Exception:
        logger.exception("Status handler failed")
        return {
            "statusCode": 500,
            "headers": {"Content-Type": "application/json"},
            "body": json.dumps({"error": "internal server error"}),
        }
