# IAM for the EBS CSI driver, via EKS Pod Identity (associated through the addon in eks.tf)
module "ebs_csi_pod_identity" {
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "~> 2.0"

  name                      = "${var.name}-ebs-csi"
  attach_aws_ebs_csi_policy = true
}

# IAM for the AWS Load Balancer Controller, via EKS Pod Identity
module "lb_controller_pod_identity" {
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "~> 2.0"

  name                            = "${var.name}-lb-controller"
  attach_aws_lb_controller_policy = true

  associations = {
    lbc = {
      cluster_name    = module.eks.cluster_name
      namespace       = "kube-system"
      service_account = local.service_accounts.lb_controller
    }
  }
}
