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
