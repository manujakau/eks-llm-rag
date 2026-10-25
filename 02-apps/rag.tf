# rag-api Deployment + internal NLB Service.
# Build and push the image first: docker buildx build --platform linux/amd64 -t <ecr_repository_url>:latest --push rag-api
module "rag" {
  source = "../modules/k8s-manifests"

  manifest_dir = "${path.module}/manifests/rag"
  template_vars = {
    image      = "${local.infra.ecr_repository_url}:${var.rag_api_image_tag}"
    nlb_name   = var.nlb_name
    vllm_url   = local.vllm_url
    tei_url    = local.tei_url
    qdrant_url = local.platform.qdrant_url
  }

  depends_on = [module.karpenter_nodes]
}
