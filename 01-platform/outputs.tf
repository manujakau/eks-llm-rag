# Read by 02-apps via terraform_remote_state
output "namespaces" { value = { for k, ns in kubernetes_namespace_v1.ns : k => ns.metadata[0].name } }

output "prometheus_url" {
  value = "http://${helm_release.kube_prometheus_stack.name}-prometheus.${helm_release.kube_prometheus_stack.namespace}.svc:9090"
}

output "qdrant_url" {
  value = "http://${helm_release.qdrant.name}.${helm_release.qdrant.namespace}:6333"
}
