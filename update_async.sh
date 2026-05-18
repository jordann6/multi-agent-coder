#!/bin/bash
set -euo pipefail

cat > agents/orchestrator.py << 'PYEOF'
import json
import os
import uuid
from datetime import datetime, timezone
from typing import Any

import boto3


def _dynamo_table():
    return boto3.resource("dynamodb", region_name=os.environ.get("AWS_REGION", "us-east-1")).Table(
        os.environ["JOBS_TABLE"]
    )


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
    boto3.client("lambda", region_name=os.environ.get("AWS_REGION", "us-east-1")).invoke(
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
PYEOF

cat > agents/coder.py << 'PYEOF'
import json
import os
from datetime import datetime, timezone
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


def _get_secret(secret_arn: str) -> str:
    client = boto3.client("secretsmanager", region_name=os.environ.get("AWS_REGION", "us-east-1"))
    return client.get_secret_value(SecretId=secret_arn)["SecretString"]


def _dynamo_table():
    return boto3.resource("dynamodb", region_name=os.environ.get("AWS_REGION", "us-east-1")).Table(
        os.environ["JOBS_TABLE"]
    )


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
    api_key = _get_secret(os.environ["ANTHROPIC_SECRET_ARN"])
    client = anthropic.Anthropic(api_key=api_key)

    messages: list[dict[str, Any]] = [{"role": "user", "content": task}]
    result: dict[str, Any] = {}

    try:
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
            result = {"task_type": "unknown", "result": {}, "summary": "Max iterations reached"}

        if job_id:
            _store_result(job_id, result)

    except Exception as e:
        if job_id:
            _store_error(job_id, str(e))
        raise

    return result
PYEOF

cat > handlers/orchestrator_handler.py << 'PYEOF'
import json

from agents.orchestrator import run_orchestrator


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

        result = run_orchestrator(task)

        return {
            "statusCode": 202,
            "headers": {"Content-Type": "application/json"},
            "body": json.dumps(result),
        }

    except Exception as e:
        return {
            "statusCode": 500,
            "headers": {"Content-Type": "application/json"},
            "body": json.dumps({"error": str(e)}),
        }
PYEOF

cat > handlers/coder_handler.py << 'PYEOF'
from agents.coder import run_coder_agent


def handler(event: dict, context: object) -> dict:
    try:
        task = (event.get("task") or "").strip()
        job_id = event.get("job_id") or None

        if not task:
            return {"error": "task field is required"}

        return run_coder_agent(task, job_id=job_id)

    except Exception as e:
        return {"error": str(e)}
PYEOF

cat > handlers/status_handler.py << 'PYEOF'
import json
import os
from decimal import Decimal

import boto3


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

        table = boto3.resource(
            "dynamodb", region_name=os.environ.get("AWS_REGION", "us-east-1")
        ).Table(os.environ["JOBS_TABLE"])

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

    except Exception as e:
        return {
            "statusCode": 500,
            "headers": {"Content-Type": "application/json"},
            "body": json.dumps({"error": str(e)}),
        }
PYEOF

cat > terraform/dynamodb.tf << 'TFEOF'
resource "aws_dynamodb_table" "jobs" {
  name         = "${var.project_name}-jobs"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "job_id"

  attribute {
    name = "job_id"
    type = "S"
  }

  ttl {
    attribute_name = "expires_at"
    enabled        = true
  }
}
TFEOF

cat > terraform/lambda.tf << 'TFEOF'
resource "aws_secretsmanager_secret" "anthropic_key" {
  name                    = "${var.project_name}/anthropic-api-key"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "anthropic_key" {
  secret_id     = aws_secretsmanager_secret.anthropic_key.id
  secret_string = var.anthropic_api_key
}

resource "aws_cloudwatch_log_group" "coder" {
  name              = "/aws/lambda/${var.project_name}-coder"
  retention_in_days = var.log_retention_days
}

resource "aws_cloudwatch_log_group" "orchestrator" {
  name              = "/aws/lambda/${var.project_name}-orchestrator"
  retention_in_days = var.log_retention_days
}

resource "aws_cloudwatch_log_group" "status" {
  name              = "/aws/lambda/${var.project_name}-status"
  retention_in_days = var.log_retention_days
}

resource "aws_lambda_function" "coder" {
  function_name    = "${var.project_name}-coder"
  filename         = "${path.module}/../dist/coder.zip"
  source_code_hash = filebase64sha256("${path.module}/../dist/coder.zip")
  handler          = "handlers.coder_handler.handler"
  runtime          = "python3.12"
  role             = aws_iam_role.coder_lambda.arn
  timeout          = 240
  memory_size      = 512

  environment {
    variables = {
      ANTHROPIC_SECRET_ARN = aws_secretsmanager_secret.anthropic_key.arn
      JOBS_TABLE           = aws_dynamodb_table.jobs.name
    }
  }

  depends_on = [aws_cloudwatch_log_group.coder]
}

resource "aws_lambda_function" "orchestrator" {
  function_name    = "${var.project_name}-orchestrator"
  filename         = "${path.module}/../dist/orchestrator.zip"
  source_code_hash = filebase64sha256("${path.module}/../dist/orchestrator.zip")
  handler          = "handlers.orchestrator_handler.handler"
  runtime          = "python3.12"
  role             = aws_iam_role.orchestrator_lambda.arn
  timeout          = 30
  memory_size      = 256

  environment {
    variables = {
      ANTHROPIC_SECRET_ARN = aws_secretsmanager_secret.anthropic_key.arn
      CODER_LAMBDA_ARN     = aws_lambda_function.coder.arn
      JOBS_TABLE           = aws_dynamodb_table.jobs.name
    }
  }

  depends_on = [aws_cloudwatch_log_group.orchestrator]
}

resource "aws_lambda_function" "status" {
  function_name    = "${var.project_name}-status"
  filename         = "${path.module}/../dist/status.zip"
  source_code_hash = filebase64sha256("${path.module}/../dist/status.zip")
  handler          = "handlers.status_handler.handler"
  runtime          = "python3.12"
  role             = aws_iam_role.status_lambda.arn
  timeout          = 10
  memory_size      = 128

  environment {
    variables = {
      JOBS_TABLE = aws_dynamodb_table.jobs.name
    }
  }

  depends_on = [aws_cloudwatch_log_group.status]
}
TFEOF

cat > terraform/iam.tf << 'TFEOF'
data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "coder_lambda" {
  name               = "${var.project_name}-coder-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
}

resource "aws_iam_role_policy_attachment" "coder_basic_execution" {
  role       = aws_iam_role.coder_lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "coder_permissions" {
  name = "${var.project_name}-coder-permissions"
  role = aws_iam_role.coder_lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue"]
        Resource = aws_secretsmanager_secret.anthropic_key.arn
      },
      {
        Effect   = "Allow"
        Action   = ["dynamodb:PutItem", "dynamodb:UpdateItem", "dynamodb:GetItem"]
        Resource = aws_dynamodb_table.jobs.arn
      }
    ]
  })
}

resource "aws_iam_role" "orchestrator_lambda" {
  name               = "${var.project_name}-orchestrator-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
}

resource "aws_iam_role_policy_attachment" "orchestrator_basic_execution" {
  role       = aws_iam_role.orchestrator_lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "orchestrator_permissions" {
  name = "${var.project_name}-orchestrator-permissions"
  role = aws_iam_role.orchestrator_lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue"]
        Resource = aws_secretsmanager_secret.anthropic_key.arn
      },
      {
        Effect   = "Allow"
        Action   = ["lambda:InvokeFunction"]
        Resource = aws_lambda_function.coder.arn
      },
      {
        Effect   = "Allow"
        Action   = ["dynamodb:PutItem", "dynamodb:UpdateItem", "dynamodb:GetItem"]
        Resource = aws_dynamodb_table.jobs.arn
      }
    ]
  })
}

resource "aws_iam_role" "status_lambda" {
  name               = "${var.project_name}-status-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
}

resource "aws_iam_role_policy_attachment" "status_basic_execution" {
  role       = aws_iam_role.status_lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "status_permissions" {
  name = "${var.project_name}-status-permissions"
  role = aws_iam_role.status_lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["dynamodb:GetItem"]
        Resource = aws_dynamodb_table.jobs.arn
      }
    ]
  })
}
TFEOF

cat > terraform/api_gateway.tf << 'TFEOF'
resource "aws_apigatewayv2_api" "main" {
  name          = "${var.project_name}-api"
  protocol_type = "HTTP"
}

resource "aws_cloudwatch_log_group" "api_gateway" {
  name              = "/aws/apigateway/${var.project_name}"
  retention_in_days = var.log_retention_days
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.main.id
  name        = "$default"
  auto_deploy = true

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_gateway.arn
    format = jsonencode({
      requestId      = "$context.requestId"
      sourceIp       = "$context.identity.sourceIp"
      requestTime    = "$context.requestTime"
      httpMethod     = "$context.httpMethod"
      routeKey       = "$context.routeKey"
      status         = "$context.status"
      responseLength = "$context.responseLength"
      errorMessage   = "$context.error.message"
    })
  }
}

resource "aws_apigatewayv2_integration" "orchestrator" {
  api_id                 = aws_apigatewayv2_api.main.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.orchestrator.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_integration" "status" {
  api_id                 = aws_apigatewayv2_api.main.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.status.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "task" {
  api_id    = aws_apigatewayv2_api.main.id
  route_key = "POST /task"
  target    = "integrations/${aws_apigatewayv2_integration.orchestrator.id}"
}

resource "aws_apigatewayv2_route" "status" {
  api_id    = aws_apigatewayv2_api.main.id
  route_key = "GET /status/{job_id}"
  target    = "integrations/${aws_apigatewayv2_integration.status.id}"
}

resource "aws_lambda_permission" "api_gateway_orchestrator" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.orchestrator.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.main.execution_arn}/*/*"
}

resource "aws_lambda_permission" "api_gateway_status" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.status.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.main.execution_arn}/*/*"
}
TFEOF

cat > terraform/outputs.tf << 'TFEOF'
output "api_endpoint" {
  description = "POST /task endpoint"
  value       = "${aws_apigatewayv2_stage.default.invoke_url}/task"
}

output "status_endpoint" {
  description = "GET /status/{job_id} base URL"
  value       = "${aws_apigatewayv2_stage.default.invoke_url}/status"
}

output "orchestrator_lambda_arn" {
  description = "ARN of the orchestrator Lambda function"
  value       = aws_lambda_function.orchestrator.arn
}

output "coder_lambda_arn" {
  description = "ARN of the coder Lambda function"
  value       = aws_lambda_function.coder.arn
}

output "status_lambda_arn" {
  description = "ARN of the status Lambda function"
  value       = aws_lambda_function.status.arn
}

output "jobs_table_name" {
  description = "DynamoDB jobs table name"
  value       = aws_dynamodb_table.jobs.name
}

output "anthropic_secret_arn" {
  description = "ARN of the Anthropic API key in Secrets Manager"
  value       = aws_secretsmanager_secret.anthropic_key.arn
}
TFEOF

cat > build.sh << 'SHEOF'
#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DIST_DIR="$ROOT_DIR/dist"

rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR"

echo "Building coder package..."
pip install anthropic boto3 \
  --target "$DIST_DIR/coder_pkg" \
  --platform manylinux2014_x86_64 \
  --python-version 3.12 \
  --implementation cp \
  --only-binary=:all: \
  --upgrade \
  --quiet
cp -r "$ROOT_DIR/agents" "$DIST_DIR/coder_pkg/"
cp -r "$ROOT_DIR/tools" "$DIST_DIR/coder_pkg/"
cp -r "$ROOT_DIR/handlers" "$DIST_DIR/coder_pkg/"
cd "$DIST_DIR/coder_pkg" && zip -r "$DIST_DIR/coder.zip" . --quiet && cd "$ROOT_DIR"
echo "  dist/coder.zip ready"

echo "Building orchestrator package..."
pip install anthropic boto3 \
  --target "$DIST_DIR/orchestrator_pkg" \
  --platform manylinux2014_x86_64 \
  --python-version 3.12 \
  --implementation cp \
  --only-binary=:all: \
  --upgrade \
  --quiet
cp -r "$ROOT_DIR/agents" "$DIST_DIR/orchestrator_pkg/"
cp -r "$ROOT_DIR/tools" "$DIST_DIR/orchestrator_pkg/"
cp -r "$ROOT_DIR/handlers" "$DIST_DIR/orchestrator_pkg/"
cd "$DIST_DIR/orchestrator_pkg" && zip -r "$DIST_DIR/orchestrator.zip" . --quiet && cd "$ROOT_DIR"
echo "  dist/orchestrator.zip ready"

echo "Building status package..."
pip install boto3 \
  --target "$DIST_DIR/status_pkg" \
  --platform manylinux2014_x86_64 \
  --python-version 3.12 \
  --implementation cp \
  --only-binary=:all: \
  --upgrade \
  --quiet
cp -r "$ROOT_DIR/handlers" "$DIST_DIR/status_pkg/"
cd "$DIST_DIR/status_pkg" && zip -r "$DIST_DIR/status.zip" . --quiet && cd "$ROOT_DIR"
echo "  dist/status.zip ready"

echo "Build complete."
