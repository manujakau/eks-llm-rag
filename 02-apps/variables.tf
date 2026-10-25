variable "images" {
  description = "Container images for the LLM services"
  type = object({
    vllm = string
    tei  = string
  })
}

variable "rag_api_image_tag" {
  description = "Tag of the rag-api image pushed to 00-infra's ECR repository"
  type        = string
}

variable "nlb_name" {
  description = "Name of the internal NLB in front of rag-api; 03-gateway reads it from this stack's outputs"
  type        = string
}

# Model serving
variable "vllm" {
  description = "vLLM server arguments"
  type = object({
    model                  = string # Hugging Face model id
    served_model_name      = string # name clients pass as "model" in API calls
    max_model_len          = number
    gpu_memory_utilization = number
    max_num_seqs           = number
  })

  validation {
    condition     = var.vllm.gpu_memory_utilization > 0 && var.vllm.gpu_memory_utilization <= 1
    error_message = "vllm.gpu_memory_utilization must be in (0, 1]."
  }
}

variable "vllm_autoscaling" {
  description = "KEDA scaling of vLLM on queued requests"
  type = object({
    min_replicas    = number
    max_replicas    = number
    queue_threshold = number # waiting requests per replica before scaling out
  })

  validation {
    condition     = var.vllm_autoscaling.min_replicas >= 1
    error_message = "min_replicas must be at least 1: the trigger metric comes from vLLM itself, so 0 replicas could never scale back up."
  }
}

variable "tei_model" {
  description = "Hugging Face embedding model id served by TEI"
  type        = string
}

# Karpenter nodes
variable "node_class" {
  description = "EC2NodeClass shared by both NodePools"
  type = object({
    ami_alias   = string # e.g. al2023@latest, or al2023@v20250101 to pin
    volume_size = string # root EBS volume, Kubernetes quantity
  })
}

variable "gpu_node_pool" {
  description = "GPU NodePool; cpu_limit caps total vCPUs and should match your G/VT instance quota"
  type = object({
    instance_families = list(string)
    instance_sizes    = list(string)
    capacity_types    = list(string)
    cpu_limit         = number
  })
}

variable "cpu_node_pool" {
  description = "CPU NodePool for TEI, rag-api and other non-GPU pods"
  type = object({
    instance_categories = list(string)
    capacity_types      = list(string)
    cpu_limit           = number
    memory_limit        = string # Kubernetes quantity
  })
}
