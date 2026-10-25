# Read by 03-gateway via terraform_remote_state
output "nlb_name" { value = var.nlb_name }

output "objects" {
  description = "Kubernetes objects applied by this stack"
  value       = merge(module.karpenter_nodes.objects, module.llm.objects, module.rag.objects)
}
