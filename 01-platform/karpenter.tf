# Karpenter – node autoscaler; IAM role, Pod Identity and SQS queue come from 00-infra.
# Its EC2NodeClass and NodePools live in 02-apps, so the CRDs exist before they are planned.
resource "helm_release" "karpenter" {
  name       = "karpenter"
  repository = "oci://public.ecr.aws/karpenter"
  chart      = "karpenter"
  version    = var.chart_versions.karpenter
  namespace  = "kube-system"

  values = [yamlencode({
    serviceAccount = { name = local.infra.karpenter_service_account }
    settings = {
      clusterName       = local.cluster
      interruptionQueue = local.infra.karpenter_queue_name
    }
  })]
}
