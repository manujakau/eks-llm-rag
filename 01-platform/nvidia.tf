# NVIDIA device plugin – advertises nvidia.com/gpu; runs on nodes labelled nvidia.com/gpu.present=true
resource "helm_release" "nvidia_device_plugin" {
  name       = "nvidia-device-plugin"
  repository = "https://nvidia.github.io/k8s-device-plugin"
  chart      = "nvidia-device-plugin"
  version    = var.chart_versions.nvidia_device_plugin
  namespace  = "kube-system"
}
