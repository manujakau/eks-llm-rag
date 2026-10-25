data "terraform_remote_state" "infra" {
  backend = "local"
  config = {
    path = "${path.module}/../00-infra/terraform.tfstate"
  }
}

data "terraform_remote_state" "apps" {
  backend = "local"
  config = {
    path = "${path.module}/../02-apps/terraform.tfstate"
  }
}

locals {
  infra = data.terraform_remote_state.infra.outputs
  apps  = data.terraform_remote_state.apps.outputs
}
