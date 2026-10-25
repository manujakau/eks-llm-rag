variable "name" {
  description = "Name for the VPC, EKS cluster and related resources; also the karpenter.sh/discovery tag value"
  type        = string
}

variable "region" {
  type = string
}

variable "tags" {
  description = "Tags for every AWS resource; exported so Karpenter's EC2NodeClass can apply them too"
  type        = map(string)
}

# VPC
variable "vpc_cidr" {
  type = string
}

variable "private_subnets" {
  description = "One CIDR per AZ; nodes and internal NLBs go here. Its length sets how many AZs are used"
  type        = list(string)
}

variable "public_subnets" {
  description = "One CIDR per AZ, same count as private_subnets"
  type        = list(string)

  validation {
    condition     = length(var.public_subnets) == length(var.private_subnets)
    error_message = "public_subnets and private_subnets must have one CIDR per AZ each."
  }
}

variable "single_nat_gateway" {
  description = "true: one NAT gateway for all AZs (cheaper, not AZ-resilient)"
  type        = bool
}

# EKS
variable "kubernetes_version" {
  description = "EKS Kubernetes version, e.g. \"1.34\"; null lets EKS pick its current default"
  type        = string
  nullable    = true
}

variable "endpoint_public_access" {
  description = "Expose the EKS API endpoint publicly (needed to run kubectl/helm from outside the VPC)"
  type        = bool
}

variable "system_node_group" {
  description = "Always-on managed node group for system pods and the Karpenter controller"
  type = object({
    ami_type       = string
    instance_types = list(string)
    min_size       = number
    max_size       = number
    desired_size   = number
  })
}

# ECR
variable "ecr_force_delete" {
  description = "Allow terraform destroy to delete the rag-api repository even if it still holds images"
  type        = bool
}
