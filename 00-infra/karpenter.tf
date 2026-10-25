# Karpenter: controller IAM role (Pod Identity), node role + access entry, interruption queue
module "karpenter" {
  source  = "terraform-aws-modules/eks/aws//modules/karpenter"
  version = "~> 21.0"

  cluster_name                  = module.eks.cluster_name
  node_iam_role_use_name_prefix = false
  node_iam_role_name            = "${var.name}-karpenter-node"
  node_iam_role_additional_policies = {
    AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  }
}
