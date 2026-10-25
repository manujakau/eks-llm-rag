name   = "llm-lab"
region = "us-east-1"
tags   = { Project = "llm-lab" }

# VPC
vpc_cidr           = "10.0.0.0/16"
private_subnets    = ["10.0.0.0/19", "10.0.32.0/19", "10.0.64.0/19"]
public_subnets     = ["10.0.96.0/22", "10.0.100.0/22", "10.0.104.0/22"]
single_nat_gateway = true # lab only: one NAT for all AZs

# EKS
kubernetes_version     = null # EKS default; pin e.g. "1.34" to control upgrades
endpoint_public_access = true # lab only: kubectl/helm from your laptop

system_node_group = {
  ami_type       = "AL2023_x86_64_STANDARD"
  instance_types = ["m6i.large"]
  min_size       = 2
  max_size       = 3
  desired_size   = 2
}

# ECR
ecr_force_delete = true # lab only: allow destroy with images inside
