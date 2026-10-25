provider "aws" {
  region = var.region
  default_tags {
    tags = merge(var.tags, { ManagedBy = "terraform" }) # does NOT reach Karpenter's instances
  }
}
