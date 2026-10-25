# KEDA – event-driven scaling for vLLM replicas
resource "helm_release" "keda" {
  name             = "keda"
  repository       = "https://kedacore.github.io/charts"
  chart            = "keda"
  version          = var.chart_versions.keda
  namespace        = "keda"
  create_namespace = true

  depends_on = [helm_release.lbc] # its Services go through the LB controller's webhook, which needs running pods
}
