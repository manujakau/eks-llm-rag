# Read 00-infra's outputs. Nothing from that stack is referenced directly:
# no module.vpc, var.region or local.name here, and no cross-stack depends_on.
data "terraform_remote_state" "infra" {
  backend = "local"
  config = {
    path = "${path.module}/../00-infra/terraform.tfstate"
  }
}
