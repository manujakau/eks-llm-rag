# AWS Load Balancer Controller – creates the internal NLB that API Gateway's VPC Link targets
resource "helm_release" "lbc" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  version    = var.chart_versions.aws_load_balancer_controller
  namespace  = "kube-system"

  values = [yamlencode({
    clusterName    = local.cluster
    region         = local.region
    vpcId          = local.infra.vpc_id
    serviceAccount = { name = local.infra.lb_controller_service_account } # matches the Pod Identity association
  })]
}
