provider "aws" {
  region = local.infra.region
  default_tags {
    tags = merge(local.infra.tags, { ManagedBy = "terraform" })
  }
}
