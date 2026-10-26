# Karpenter – node autoscaler; IAM role, Pod Identity and SQS queue come from 00-infra.
# Its EC2NodeClass and NodePools live in 02-apps, so the CRDs exist before they are planned.
resource "helm_release" "karpenter" {
  name       = "karpenter"
  repository = "oci://public.ecr.aws/karpenter"
  chart      = "karpenter"
  version    = var.chart_versions.karpenter
  namespace  = "kube-system"

  values = [yamlencode({
    # the chart's required anti-affinity allows one replica per system node, and 00-infra runs one;
    # a second replica would stay Pending
    replicas       = 1
    serviceAccount = { name = local.infra.karpenter_service_account }
    settings = {
      clusterName       = local.cluster
      interruptionQueue = local.infra.karpenter_queue_name
    }
    # feeds llm:gpu_node_hourly_cost:usd (02-apps llm-rules.yaml). Karpenter exposes ~32k series, ~10k of them
    # prices for every instance type; keep spot g4dn/g6 prices and the CPU-allocatable series of GPU nodes,
    # which carry each node's instance_type, capacity_type and zone (a few dozen series in all)
    serviceMonitor = {
      enabled = true
      metricRelabelings = [{
        action       = "keep"
        sourceLabels = ["__name__", "instance_type", "capacity_type", "nodepool", "resource_type"]
        regex        = "karpenter_cloudprovider_instance_type_offering_price_estimate;(g4dn|g6)\\..*;spot;;|karpenter_nodes_allocatable;.*;.*;gpu;cpu"
      }]
    }
  })]

  # its Services go through the LB controller's webhook, which needs running pods; the chart only renders the
  # ServiceMonitor when the Prometheus Operator CRDs already exist
  depends_on = [helm_release.lbc, helm_release.kube_prometheus_stack]
}
