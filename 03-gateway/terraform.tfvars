api_name               = "rag-api"
stage_name             = "v1"
integration_timeout_ms = 29000 # LLM answers can be slow; this is the REST API maximum

usage_plan = {
  rate_limit  = 5 # requests per second
  burst_limit = 10
  daily_quota = 10000
}
