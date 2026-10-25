# Read by 01-platform, 02-apps and 03-gateway via terraform_remote_state
output "region" { value = var.region }
output "tags" { value = var.tags }
output "cluster_name" { value = module.eks.cluster_name }
output "cluster_endpoint" { value = module.eks.cluster_endpoint }
output "cluster_certificate_authority_data" { value = module.eks.cluster_certificate_authority_data }
output "vpc_id" { value = module.vpc.vpc_id }
output "private_subnets" { value = module.vpc.private_subnets }
output "node_security_group_id" { value = module.eks.node_security_group_id }
output "ecr_repository_url" { value = aws_ecr_repository.rag_api.repository_url }
output "karpenter_node_role_name" { value = module.karpenter.node_iam_role_name }
output "karpenter_queue_name" { value = module.karpenter.queue_name }
output "karpenter_service_account" { value = module.karpenter.service_account }
output "lb_controller_service_account" { value = local.service_accounts.lb_controller }
