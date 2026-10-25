# Internal NLB created by the rag-api Service in 02-apps
data "aws_lb" "rag" { name = local.apps.nlb_name }

# The LB controller creates the NLB after 02-apps finishes and it stays "provisioning" for a few minutes;
# a VPC Link created before it is active ends up FAILED. Polls every 15 s for up to 10 min.
resource "terraform_data" "wait_for_nlb" {
  triggers_replace = [data.aws_lb.rag.arn]

  provisioner "local-exec" {
    command = "aws elbv2 wait load-balancer-available --region ${local.infra.region} --load-balancer-arns ${data.aws_lb.rag.arn}"
  }
}

resource "aws_api_gateway_vpc_link" "rag" {
  name        = var.api_name
  target_arns = [data.aws_lb.rag.arn]

  depends_on = [terraform_data.wait_for_nlb]
}
