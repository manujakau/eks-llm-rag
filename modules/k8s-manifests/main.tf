# Every file is rendered with templatefile(), so plain .yaml and .yaml.tftpl behave the same;
# .tftpl only signals that the file uses variables. Keys drop the .tftpl suffix, so renaming
# foo.yaml to foo.yaml.tftpl keeps the same resource address.
locals {
  manifests = {
    for f in fileset(var.manifest_dir, "*.{yaml,yaml.tftpl}") :
    trimsuffix(f, ".tftpl") => yamldecode(templatefile("${var.manifest_dir}/${f}", var.template_vars))
  }
}

resource "kubernetes_manifest" "this" {
  for_each = local.manifests

  manifest = each.value
}
