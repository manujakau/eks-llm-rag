locals {
  infra    = data.terraform_remote_state.infra.outputs
  cluster  = local.infra.cluster_name
  region   = local.infra.region
  k8s_host = local.infra.cluster_endpoint
  k8s_ca   = base64decode(local.infra.cluster_certificate_authority_data)
  k8s_exec = {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", local.cluster, "--region", local.region]
  }
}
