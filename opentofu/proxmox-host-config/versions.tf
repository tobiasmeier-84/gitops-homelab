terraform {
  required_version = ">= 1.7.0"

  required_providers {
    null = {
      source  = "hashicorp/null"
      version = ">= 3.2.0"
    }
  }

  backend "s3" {
    bucket                      = "opentofu-state"
    key                         = "proxmox-host-config/terraform.tfstate"
    endpoint                    = "https://iapetus.orbit.solsys.dev:9000"
    region                      = "us-east-1"
    skip_credentials_validation = true
    skip_region_validation      = true
    skip_metadata_api_check     = true
    use_path_style               = true
  }
}