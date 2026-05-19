resource "aws_secretsmanager_secret" "anthropic_key" {
  name                    = "${var.project_name}/anthropic-api-key"
  recovery_window_in_days = 7
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
      MODEL_ID             = var.model_id
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
      CODER_LAMBDA_ARN = aws_lambda_function.coder.arn
      JOBS_TABLE       = aws_dynamodb_table.jobs.name
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

resource "aws_cloudwatch_log_group" "auth" {
  name              = "/aws/lambda/${var.project_name}-auth"
  retention_in_days = var.log_retention_days
}

resource "aws_lambda_function" "auth" {
  function_name    = "${var.project_name}-auth"
  filename         = "${path.module}/../dist/auth.zip"
  source_code_hash = filebase64sha256("${path.module}/../dist/auth.zip")
  handler          = "handlers.auth_handler.handler"
  runtime          = "python3.12"
  role             = aws_iam_role.auth_lambda.arn
  timeout          = 5
  memory_size      = 128

  environment {
    variables = {
      API_KEY = var.api_gateway_key
    }
  }

  depends_on = [aws_cloudwatch_log_group.auth]
}
