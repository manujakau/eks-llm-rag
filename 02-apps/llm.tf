# vLLM, TEI, KEDA ScaledObject, ServiceMonitor and alert rules
module "llm" {
  source = "../modules/k8s-manifests"

  manifest_dir = "${path.module}/manifests/llm"
  template_vars = {
    vllm_image     = var.images.vllm
    tei_image      = var.images.tei
    vllm           = var.vllm
    autoscaling    = var.vllm_autoscaling
    tei_model      = var.tei_model
    prometheus_url = local.platform.prometheus_url
  }

  depends_on = [module.karpenter_nodes] # on destroy, remove workloads before their NodePools
}
