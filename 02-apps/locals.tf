locals {
  infra    = data.terraform_remote_state.infra.outputs
  platform = data.terraform_remote_state.platform.outputs
  cluster  = local.infra.cluster_name

  # In-cluster URLs of the services in manifests/llm, passed to rag-api
  vllm_url = "http://vllm.${local.platform.namespaces.llm}:8000/v1"
  tei_url  = "http://tei.${local.platform.namespaces.llm}:8080"
}
