data "aws_availability_zones" "available" { state = "available" }

locals {
  azs = slice(data.aws_availability_zones.available.names, 0, length(var.private_subnets))

  # Service accounts the Pod Identity roles are bound to; 01-platform installs the charts with these names
  service_accounts = {
    ebs_csi       = "ebs-csi-controller-sa"
    lb_controller = "aws-load-balancer-controller"
  }
}
