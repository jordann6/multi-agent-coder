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

variable "api_gateway_key" {
  description = "Shared secret callers must supply in the x-api-key header"
  type        = string
  sensitive   = true
}

variable "model_id" {
  description = "Claude model ID used by the coder agent"
  type        = string
  default     = "claude-sonnet-4-6"
}

variable "log_retention_days" {
  description = "CloudWatch log retention in days"
  type        = number
  default     = 14
}

variable "api_throttle_rate" {
  description = "Steady-state requests per second allowed by API Gateway"
  type        = number
  default     = 10
}

variable "api_throttle_burst" {
  description = "Maximum burst of requests API Gateway will accept"
  type        = number
  default     = 20
}
