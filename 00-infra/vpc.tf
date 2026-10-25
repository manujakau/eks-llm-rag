module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 6.0"

  name            = var.name
  cidr            = var.vpc_cidr
  azs             = local.azs
  private_subnets = var.private_subnets
  public_subnets  = var.public_subnets

  enable_nat_gateway = true
  single_nat_gateway = var.single_nat_gateway

  public_subnet_tags = { "kubernetes.io/role/elb" = 1 }
  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = 1        # where the LB controller puts internal NLBs
    "karpenter.sh/discovery"          = var.name # where Karpenter launches nodes
  }
}
