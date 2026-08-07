terraform {
  required_version = ">= 1.7.0"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = ">= 0.111.0"
    }
  }

  backend "s3" {
    bucket                      = "opentofu-state"
    key                         = "proxmox-acme/terraform.tfstate"
    endpoint                    = "https://iapetus.orbit.solsys.dev:9000"
    region                      = "us-east-1"
    skip_credentials_validation = true
    skip_region_validation      = true
    skip_metadata_api_check     = true
    use_path_style               = true
  }
}

provider "proxmox" {
  endpoint = var.pve_api_endpoint
  username = "root@pam"
  password = var.pve_root_password
  insecure = false
}