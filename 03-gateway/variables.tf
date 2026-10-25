variable "api_name" {
  description = "Name for the REST API, VPC Link, usage plan and API key"
  type        = string
}

variable "stage_name" {
  description = "API Gateway stage; becomes the first path segment of the invoke URL"
  type        = string
}

variable "integration_timeout_ms" {
  description = "Backend timeout for the rag-api integration; REST APIs allow 50–29000 ms by default"
  type        = number

  validation {
    condition     = var.integration_timeout_ms >= 50 && var.integration_timeout_ms <= 29000
    error_message = "integration_timeout_ms must be between 50 and 29000 unless the account's limit was raised."
  }
}

variable "usage_plan" {
  description = "Throttling and daily quota for the rag-api API key"
  type = object({
    rate_limit  = number
    burst_limit = number
    daily_quota = number
  })
}
