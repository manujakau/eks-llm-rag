output "objects" {
  description = "Applied objects, file name => Kind/namespace/name"
  value = {
    for f, m in kubernetes_manifest.this :
    f => join("/", compact([m.manifest.kind, try(m.manifest.metadata.namespace, ""), m.manifest.metadata.name]))
  }
}
