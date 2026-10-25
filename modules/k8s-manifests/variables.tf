variable "manifest_dir" {
  description = "Directory of Kubernetes manifests, one object per file (*.yaml or *.yaml.tftpl)"
  type        = string
}

variable "template_vars" {
  description = "Values available as $${name} in every manifest; literal $${ or %%{ must be escaped as $$${ / %%%{"
  type        = any
  default     = {}
}
