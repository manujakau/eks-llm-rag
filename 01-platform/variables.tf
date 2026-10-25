variable "chart_versions" {
  description = "Pinned Helm chart versions"
  type = object({
    karpenter                    = string
    aws_load_balancer_controller = string
    nvidia_device_plugin         = string
    kube_prometheus_stack        = string
    keda                         = string
    qdrant                       = string
  })
}
