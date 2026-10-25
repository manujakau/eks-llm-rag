# Karpenter EC2NodeClass + GPU/CPU NodePools. Their CRDs come from 01-platform's Helm release,
# which is applied first, so kubernetes_manifest can plan them without a -target pass.
module "karpenter_nodes" {
  source = "../modules/k8s-manifests"

  manifest_dir = "${path.module}/manifests/karpenter"
  template_vars = {
    cluster_name   = local.cluster
    node_role_name = local.infra.karpenter_node_role_name
    tags           = local.infra.tags
    node           = var.node_class
    gpu            = var.gpu_node_pool
    cpu            = var.cpu_node_pool
  }
}
