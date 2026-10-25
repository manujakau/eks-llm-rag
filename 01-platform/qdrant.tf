# Qdrant vector database (used by the RAG API); ClusterIP only, rag-api reaches it in-cluster
resource "helm_release" "qdrant" {
  name       = "qdrant"
  repository = "https://qdrant.github.io/qdrant-helm"
  chart      = "qdrant"
  version    = var.chart_versions.qdrant
  namespace  = kubernetes_namespace_v1.ns["rag"].metadata[0].name

  # lbc: its Services go through the LB controller's webhook, which needs running pods
  depends_on = [kubernetes_storage_class_v1.gp3, helm_release.lbc]
}
