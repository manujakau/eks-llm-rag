# api_key_required = true in api.tf rejects every call without a key that belongs to a usage plan
resource "aws_api_gateway_usage_plan" "rag" {
  name = var.api_name

  api_stages {
    api_id = aws_api_gateway_rest_api.rag.id
    stage  = aws_api_gateway_stage.v1.stage_name
  }

  throttle_settings {
    rate_limit  = var.usage_plan.rate_limit
    burst_limit = var.usage_plan.burst_limit
  }

  quota_settings {
    limit  = var.usage_plan.daily_quota
    period = "DAY"
  }
}

resource "aws_api_gateway_api_key" "rag" {
  name = var.api_name
}

resource "aws_api_gateway_usage_plan_key" "rag" {
  key_id        = aws_api_gateway_api_key.rag.id
  key_type      = "API_KEY"
  usage_plan_id = aws_api_gateway_usage_plan.rag.id
}
