terraform {
  required_version = ">= 1.7.0"

  required_providers {
    routeros = {
      source  = "terraform-routeros/routeros"
      version = "~> 1.99.0"
    }
  }

  backend "s3" {
    bucket                      = "opentofu-state"
    key                         = "medina/terraform.tfstate"
    endpoint                    = "https://iapetus.orbit.solsys.dev:9000"
    region                      = "us-east-1"
    skip_credentials_validation = true
    skip_region_validation      = true
    skip_metadata_api_check     = true
    use_path_style               = true
  }
}

provider "routeros" {
  hosturl  = "https://192.168.88.1"
  username = "admin"
  password = var.router_password
  insecure = true
}