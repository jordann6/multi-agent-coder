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
