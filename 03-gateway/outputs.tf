output "invoke_url" { value = aws_api_gateway_stage.v1.invoke_url }
output "api_key" {
  value     = aws_api_gateway_api_key.rag.value
  sensitive = true # terraform output -raw api_key
}
