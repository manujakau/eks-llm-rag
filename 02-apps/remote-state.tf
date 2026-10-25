data "terraform_remote_state" "infra" {
  backend = "local"
  config = {
    path = "${path.module}/../00-infra/terraform.tfstate"
  }
}

data "terraform_remote_state" "platform" {
  backend = "local"
  config = {
    path = "${path.module}/../01-platform/terraform.tfstate"
  }
}
