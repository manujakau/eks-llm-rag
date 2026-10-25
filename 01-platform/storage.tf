# Namespaces + default StorageClass
resource "kubernetes_namespace_v1" "ns" {
  for_each = toset(["llm", "rag"])
  metadata {
    name = each.key
  }
}

resource "kubernetes_storage_class_v1" "gp3" {
  metadata {
    name        = "gp3"
    annotations = { "storageclass.kubernetes.io/is-default-class" = "true" }
  }
  storage_provisioner = "ebs.csi.aws.com" # the EBS CSI add-on from 00-infra
  volume_binding_mode = "WaitForFirstConsumer"
  parameters          = { type = "gp3", encrypted = "true" }
}
