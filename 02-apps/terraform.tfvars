images = {
  vllm = "vllm/vllm-openai:v0.32.0"
  tei  = "ghcr.io/huggingface/text-embeddings-inference:cpu-1.9"
}

rag_api_image_tag = "latest"
nlb_name          = "rag-api-nlb"

# Model serving
vllm = {
  model                  = "Qwen/Qwen3-4B-Instruct-2507"
  served_model_name      = "qwen3-4b"
  max_model_len          = 8192
  gpu_memory_utilization = 0.90
  max_num_seqs           = 64
}

# To pause overnight, annotate the ScaledObject with autoscaling.keda.sh/paused-replicas: "0"
vllm_autoscaling = {
  min_replicas    = 1
  max_replicas    = 2 # one GPU per replica; gpu_node_pool.cpu_limit (8) fits two g6.xlarge
  queue_threshold = 10
}

tei_model = "BAAI/bge-base-en-v1.5"

# Karpenter nodes
node_class = {
  ami_alias   = "al2023@latest"
  volume_size = "100Gi"
}

gpu_node_pool = {
  instance_families = ["g6"] # NVIDIA L4
  instance_sizes    = ["xlarge"]
  capacity_types    = ["spot"] # "spot", "on-demand"; spot uses the "All G and VT Spot Instance Requests" quota
  # 8 vCPU = at most two xlarge nodes, matching vllm_autoscaling.max_replicas; with one replica running this
  # leaves room for Karpenter's replace-before-remove, at two it waits until load drops
  cpu_limit = 8
}

cpu_node_pool = {
  instance_categories = ["c", "m", "r"]
  capacity_types      = ["spot"] # "spot", "on-demand"
  # cost guard: workloads here request ~4 vCPU / 8Gi, so this is one node plus room for a replacement
  cpu_limit    = 16
  memory_limit = "64Gi"
}
