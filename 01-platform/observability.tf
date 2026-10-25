# Prometheus + Grafana – scrapes vLLM, evaluates PrometheusRules, feeds KEDA
resource "helm_release" "kube_prometheus_stack" {
  name             = "kube-prometheus-stack"
  repository       = "https://prometheus-community.github.io/helm-charts"
  chart            = "kube-prometheus-stack"
  version          = var.chart_versions.kube_prometheus_stack
  namespace        = "monitoring"
  create_namespace = true

  values = [yamlencode({
    prometheus = {
      prometheusSpec = {
        # pick up ServiceMonitors/PrometheusRules from every namespace, not only this release's
        serviceMonitorSelectorNilUsesHelmValues = false
        ruleSelectorNilUsesHelmValues           = false
      }
    }
  })]
}
