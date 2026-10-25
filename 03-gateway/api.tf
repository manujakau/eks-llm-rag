resource "aws_api_gateway_rest_api" "rag" {
  name = var.api_name
  endpoint_configuration { types = ["REGIONAL"] }
}

resource "aws_api_gateway_resource" "proxy" {
  rest_api_id = aws_api_gateway_rest_api.rag.id
  parent_id   = aws_api_gateway_rest_api.rag.root_resource_id
  path_part   = "{proxy+}"
}

resource "aws_api_gateway_method" "proxy" {
  rest_api_id        = aws_api_gateway_rest_api.rag.id
  resource_id        = aws_api_gateway_resource.proxy.id
  http_method        = "ANY"
  authorization      = "NONE"
  api_key_required   = true
  request_parameters = { "method.request.path.proxy" = true }
}

resource "aws_api_gateway_integration" "proxy" {
  rest_api_id             = aws_api_gateway_rest_api.rag.id
  resource_id             = aws_api_gateway_resource.proxy.id
  http_method             = aws_api_gateway_method.proxy.http_method
  type                    = "HTTP_PROXY"
  integration_http_method = "ANY"
  connection_type         = "VPC_LINK"
  connection_id           = aws_api_gateway_vpc_link.rag.id
  uri                     = "http://${data.aws_lb.rag.dns_name}/{proxy}"
  timeout_milliseconds    = var.integration_timeout_ms
  request_parameters      = { "integration.request.path.proxy" = "method.request.path.proxy" }
}

resource "aws_api_gateway_deployment" "rag" {
  rest_api_id = aws_api_gateway_rest_api.rag.id
  triggers = {
    redeploy = sha1(jsonencode([aws_api_gateway_resource.proxy,
      aws_api_gateway_method.proxy,
    aws_api_gateway_integration.proxy]))
  }
  lifecycle { create_before_destroy = true }
}

resource "aws_api_gateway_stage" "v1" {
  rest_api_id   = aws_api_gateway_rest_api.rag.id
  deployment_id = aws_api_gateway_deployment.rag.id
  stage_name    = var.stage_name
}
