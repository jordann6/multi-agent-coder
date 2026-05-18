#!/bin/bash
set -euo pipefail

mkdir -p agents tools handlers terraform dist

touch agents/__init__.py tools/__init__.py handlers/__init__.py

cat > tools/registry.py << 'PYEOF'
CODER_TOOLS = [
    {
        "name": "write_code",
        "description": (
            "Generate a language-appropriate scaffold and structural hints to guide "
            "code writing for the given task."
        ),
        "input_schema": {
            "type": "object",
            "properties": {
                "language": {
                    "type": "string",
                    "description": "Programming language such as python, javascript, bash, go, typescript"
                },
                "task": {
                    "type": "string",
                    "description": "Description of what the code should accomplish"
                }
            },
            "required": ["language", "task"]
        }
    },
    {
        "name": "explain_code",
        "description": (
            "Analyze a code block and return structural metadata including detected "
            "functions, classes, imports, and line count to inform a plain-language explanation."
        ),
        "input_schema": {
            "type": "object",
            "properties": {
                "code": {
                    "type": "string",
                    "description": "The code block to analyze"
                },
                "language": {
                    "type": "string",
                    "description": "The programming language of the code block"
                }
            },
            "required": ["code", "language"]
        }
    },
    {
        "name": "debug_code",
        "description": (
            "Analyze code and an error message to classify the bug type and return "
            "structured diagnostic information."
        ),
        "input_schema": {
            "type": "object",
            "properties": {
                "code": {
                    "type": "string",
                    "description": "The code that contains the bug"
                },
                "error": {
                    "type": "string",
                    "description": "The error message or description of unexpected behavior"
                },
                "language": {
                    "type": "string",
                    "description": "The programming language of the code"
                }
            },
            "required": ["code", "error", "language"]
        }
    }
]

ORCHESTRATOR_TOOLS = [
    {
        "name": "invoke_coder",
        "description": (
            "Route a coding task to the Coder specialist agent. Use for tasks "
            "involving writing, explaining, or debugging code."
        ),
        "input_schema": {
            "type": "object",
            "properties": {
                "task": {
                    "type": "string",
                    "description": "The full task description to send to the Coder specialist"
                }
            },
            "required": ["task"]
        }
    }
]
PYEOF

cat > tools/code_tools.py << 'PYEOF'
import ast
import re
from typing import Any


def write_code(language: str, task: str) -> dict[str, Any]:
    language = language.lower().strip()

    scaffolds: dict[str, dict[str, str]] = {
        "python": {
            "entry_point": "def main():",
            "error_handling": "try/except with specific exception types",
            "imports_hint": "standard library preferred; minimize third-party deps",
            "style": "PEP8, type hints encouraged",
            "template": (
                "# Task: {task}\n"
                "from typing import Any\n\n\n"
                "def main() -> Any:\n"
                "    pass\n\n\n"
                "if __name__ == '__main__':\n"
                "    main()\n"
            ),
        },
        "javascript": {
            "entry_point": "const main = () =>",
            "error_handling": "try/catch",
            "imports_hint": "ESModules preferred (import/export)",
            "style": "camelCase, const over let",
            "template": (
                "// Task: {task}\n\n"
                "const main = () => {{\n"
                "  // implementation\n"
                "}};\n\n"
                "module.exports = {{ main }};\n"
            ),
        },
        "typescript": {
            "entry_point": "const main = (): ReturnType =>",
            "error_handling": "try/catch with typed errors",
            "imports_hint": "ESModules, explicit type imports",
            "style": "strict mode, explicit return types",
            "template": (
                "// Task: {task}\n\n"
                "const main = (): void => {{\n"
                "  // implementation\n"
                "}};\n\n"
                "export {{ main }};\n"
            ),
        },
        "bash": {
            "entry_point": "#!/bin/bash",
            "error_handling": "set -euo pipefail at top of file",
            "imports_hint": "prefer built-ins; avoid external deps where possible",
            "style": "SCREAMING_SNAKE_CASE for constants, snake_case for locals",
            "template": (
                "#!/bin/bash\n"
                "# Task: {task}\n"
                "set -euo pipefail\n\n"
                "main() {{\n"
                "  echo 'implement here'\n"
                "}}\n\n"
                "main \"$@\"\n"
            ),
        },
        "go": {
            "entry_point": "func main()",
            "error_handling": "explicit error returns; no panic in library code",
            "imports_hint": "standard library first; group stdlib vs external imports",
            "style": "gofmt, exported symbols capitalized",
            "template": (
                "// Task: {task}\n"
                "package main\n\n"
                "import \"fmt\"\n\n"
                "func main() {{\n"
                "    fmt.Println(\"implement here\")\n"
                "}}\n"
            ),
        },
    }

    scaffold = scaffolds.get(
        language,
        {
            "entry_point": "language-specific entry point",
            "error_handling": "language-appropriate error handling",
            "imports_hint": "minimize dependencies",
            "style": "follow community conventions",
            "template": "// Task: {task}\n// implement here\n",
        },
    )

    return {
        "language": language,
        "task": task,
        "scaffold": scaffold["template"].format(task=task),
        "hints": {
            "entry_point": scaffold["entry_point"],
            "error_handling": scaffold["error_handling"],
            "imports": scaffold["imports_hint"],
            "style": scaffold["style"],
        },
    }


def explain_code(code: str, language: str) -> dict[str, Any]:
    language = language.lower().strip()
    result: dict[str, Any] = {
        "language": language,
        "line_count": len(code.splitlines()),
        "char_count": len(code),
        "structure": {},
    }

    if language == "python":
        try:
            tree = ast.parse(code)
            functions = [
                node.name
                for node in ast.walk(tree)
                if isinstance(node, ast.FunctionDef)
            ]
            classes = [
                node.name
                for node in ast.walk(tree)
                if isinstance(node, ast.ClassDef)
            ]
            imports: list[str] = []
            for node in ast.walk(tree):
                if isinstance(node, ast.Import):
                    imports.extend(alias.name for alias in node.names)
                elif isinstance(node, ast.ImportFrom):
                    imports.append(node.module or "")

            result["structure"] = {
                "functions": functions,
                "classes": classes,
                "imports": list(set(filter(None, imports))),
                "syntax_valid": True,
            }
        except SyntaxError as e:
            result["structure"] = {
                "syntax_valid": False,
                "syntax_error": str(e),
            }
    else:
        func_patterns = {
            "javascript": r"(?:function\s+(\w+)|const\s+(\w+)\s*=\s*(?:async\s*)?\()",
            "typescript": r"(?:function\s+(\w+)|const\s+(\w+)\s*=\s*(?:async\s*)?\()",
            "bash": r"^(\w+)\s*\(\)",
            "go": r"func\s+(\w+)\s*\(",
        }
        pattern = func_patterns.get(language, "")
        functions_found: list[str] = []
        if pattern:
            for match in re.finditer(pattern, code, re.MULTILINE):
                name = next((g for g in match.groups() if g), None)
                if name:
                    functions_found.append(name)
        result["structure"] = {"detected_functions": functions_found}

    return result


def debug_code(code: str, error: str, language: str) -> dict[str, Any]:
    language = language.lower().strip()

    error_patterns = [
        (
            r"NameError|ReferenceError|undefined",
            "undefined_variable",
            "A variable or function is referenced before it is defined or is out of scope.",
        ),
        (
            r"TypeError|type error|cannot read propert",
            "type_error",
            "An operation is being performed on an incompatible type.",
        ),
        (
            r"IndexError|index out of range|out of bounds",
            "index_error",
            "A sequence is being accessed at an index that does not exist.",
        ),
        (
            r"KeyError|key not found",
            "key_error",
            "A dictionary key does not exist.",
        ),
        (
            r"SyntaxError|syntax error|unexpected token|parse error",
            "syntax_error",
            "The code has a structural issue that prevents parsing.",
        ),
        (
            r"ImportError|ModuleNotFoundError|cannot find module",
            "import_error",
            "A module or package is missing or not installed.",
        ),
        (
            r"AttributeError|has no attribute|is not a function",
            "attribute_error",
            "An attribute or method does not exist on this object.",
        ),
        (
            r"ZeroDivisionError|division by zero",
            "division_error",
            "A division by zero is occurring.",
        ),
        (
            r"ConnectionError|ECONNREFUSED|timeout|ETIMEDOUT",
            "connection_error",
            "A network connection failed or timed out.",
        ),
        (
            r"PermissionError|EACCES|permission denied",
            "permission_error",
            "The process lacks permission to access a file or resource.",
        ),
    ]

    detected_type = "unknown_error"
    detected_description = "Error type could not be automatically classified."

    for pattern, error_type, description in error_patterns:
        if re.search(pattern, error, re.IGNORECASE):
            detected_type = error_type
            detected_description = description
            break

    result: dict[str, Any] = {
        "language": language,
        "error_type": detected_type,
        "error_description": detected_description,
        "raw_error": error,
        "line_count": len(code.splitlines()),
    }

    if language == "python":
        try:
            ast.parse(code)
            result["syntax_valid"] = True
        except SyntaxError as e:
            result["syntax_valid"] = False
            result["syntax_note"] = str(e)

    return result


TOOL_DISPATCH: dict[str, Any] = {
    "write_code": write_code,
    "explain_code": explain_code,
    "debug_code": debug_code,
}
PYEOF

cat > agents/coder.py << 'PYEOF'
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
PYEOF

cat > agents/orchestrator.py << 'PYEOF'
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
            "statusCode": 200,
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

        if not task:
            return {"error": "task field is required"}

        return run_coder_agent(task)

    except Exception as e:
        return {"error": str(e)}
PYEOF

cat > terraform/variables.tf << 'TFEOF'
variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project name prefix for all resources"
  type        = string
  default     = "multi-agent-coder"
}

variable "anthropic_api_key" {
  description = "Anthropic API key"
  type        = string
  sensitive   = true
}

variable "log_retention_days" {
  description = "CloudWatch log retention in days"
  type        = number
  default     = 14
}
TFEOF

cat > terraform/main.tf << 'TFEOF'
terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket = "tf-backend-jord-projs"
    key    = "multi-agent-coder/terraform.tfstate"
    region = "us-east-1"
  }
}

provider "aws" {
  region = var.aws_region
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
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

resource "aws_iam_role_policy" "coder_secrets" {
  name = "${var.project_name}-coder-secrets"
  role = aws_iam_role.coder_lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue"]
        Resource = aws_secretsmanager_secret.anthropic_key.arn
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
      }
    ]
  })
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
  timeout          = 300
  memory_size      = 512

  environment {
    variables = {
      ANTHROPIC_SECRET_ARN = aws_secretsmanager_secret.anthropic_key.arn
      CODER_LAMBDA_ARN     = aws_lambda_function.coder.arn
    }
  }

  depends_on = [aws_cloudwatch_log_group.orchestrator]
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
  }
}

resource "aws_apigatewayv2_integration" "orchestrator" {
  api_id                 = aws_apigatewayv2_api.main.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.orchestrator.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "task" {
  api_id    = aws_apigatewayv2_api.main.id
  route_key = "POST /task"
  target    = "integrations/${aws_apigatewayv2_integration.orchestrator.id}"
}

resource "aws_lambda_permission" "api_gateway_orchestrator" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.orchestrator.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.main.execution_arn}/*/*"
}

output "api_endpoint" {
  description = "API Gateway endpoint for POST /task"
  value       = "${aws_apigatewayv2_stage.default.invoke_url}/task"
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
pip install anthropic boto3 --target "$DIST_DIR/coder_pkg" --quiet
cp -r "$ROOT_DIR/agents" "$DIST_DIR/coder_pkg/"
cp -r "$ROOT_DIR/tools" "$DIST_DIR/coder_pkg/"
cp -r "$ROOT_DIR/handlers" "$DIST_DIR/coder_pkg/"
cd "$DIST_DIR/coder_pkg" && zip -r "$DIST_DIR/coder.zip" . --quiet && cd "$ROOT_DIR"
echo "  dist/coder.zip ready"

echo "Building orchestrator package..."
pip install anthropic boto3 --target "$DIST_DIR/orchestrator_pkg" --quiet
cp -r "$ROOT_DIR/agents" "$DIST_DIR/orchestrator_pkg/"
cp -r "$ROOT_DIR/tools" "$DIST_DIR/orchestrator_pkg/"
cp -r "$ROOT_DIR/handlers" "$DIST_DIR/orchestrator_pkg/"
cd "$DIST_DIR/orchestrator_pkg" && zip -r "$DIST_DIR/orchestrator.zip" . --quiet && cd "$ROOT_DIR"
echo "  dist/orchestrator.zip ready"

echo "Build complete."
SHEOF

cat > requirements.txt << 'EOF'
anthropic>=0.40.0
boto3>=1.35.0
EOF

cat > .gitignore << 'EOF'
.venv/
dist/
.env
__pycache__/
*.pyc
*.zip
EOF

cat > README.md << 'EOF'
# multi-agent-coder

A multi-agent system deployed on AWS Lambda that routes natural language coding tasks to specialist agents via an orchestrator. The orchestrator receives a task over HTTP, delegates to a Coder specialist Lambda, and returns a structured result. Built with the Anthropic SDK tool-use pattern and fully provisioned with Terraform.

## Architecture

```
Client
  POST /task
    API Gateway (HTTP API)
      Orchestrator Lambda
        invoke() → Coder Lambda
                      tool-use loop (write_code | explain_code | debug_code)
                      returns structured JSON result
        synthesizes → final response
```

## Supported task types

| Type | Example prompt |
|---|---|
| write_code | "Write a Python function that flattens a nested list" |
| explain_code | "Explain what this Go function does: ..." |
| debug_code | "Debug this JavaScript: ... Error: Cannot read property of undefined" |

## Deploy

```bash
chmod +x build.sh && ./build.sh
cd terraform
terraform init
terraform apply -var="anthropic_api_key=sk-ant-..."
```

## Test

```bash
curl -X POST <API_ENDPOINT> \
  -H "Content-Type: application/json" \
  -d '{"task": "Write a Python function that flattens a nested list"}'
```

## Teardown

```bash
cd terraform
terraform destroy -var="anthropic_api_key=placeholder"
```
EOF

chmod +x build.sh

echo ""
echo "All files written. Run these next:"
echo ""
echo "  python3 -m venv .venv"
echo "  source .venv/bin/activate"
echo "  pip install -r requirements.txt"
echo "  git init && git add . && git commit -m 'initial commit'"
echo "  code ."
