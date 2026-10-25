module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.0"

  name                                     = var.name
  kubernetes_version                       = var.kubernetes_version
  endpoint_public_access                   = var.endpoint_public_access
  enable_cluster_creator_admin_permissions = true

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  addons = {
    vpc-cni                = { before_compute = true }
    eks-pod-identity-agent = { before_compute = true }
    kube-proxy             = {}
    coredns                = {}
    aws-ebs-csi-driver = {
      pod_identity_association = [{
        role_arn        = module.ebs_csi_pod_identity.iam_role_arn
        service_account = local.service_accounts.ebs_csi
      }]
    }
  }

  # Small always-on group for system pods and the Karpenter controller; GPU nodes come from Karpenter
  eks_managed_node_groups = {
    system = var.system_node_group
  }

  node_security_group_tags = { "karpenter.sh/discovery" = var.name } # SGs Karpenter attaches to nodes
}
