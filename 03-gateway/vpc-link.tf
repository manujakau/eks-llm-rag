# Internal NLB created by the rag-api Service in 02-apps
data "aws_lb" "rag" { name = local.apps.nlb_name }

resource "aws_api_gateway_vpc_link" "rag" {
  name        = var.api_name
  target_arns = [data.aws_lb.rag.arn]
}
