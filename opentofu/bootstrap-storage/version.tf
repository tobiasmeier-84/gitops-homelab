terraform {
  required_version = ">= 1.7.0"  # OpenTofu

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = ">= 0.111.0"
    }
    null = {
      source  = "hashicorp/null"
      version = ">= 3.2.0"
    }
  }

# Remote state via the self-hosted MinIO instance (iapetus) — see ADR-0024.
# Originally used local state during bootstrap, before iapetus existed;
# migrated once iapetus was up and the state bucket created.

  backend "s3" {
    bucket                      = "opentofu-state"
    key                         = "bootstrap-storage/terraform.tfstate"
    endpoint                    = "https://iapetus.orbit.solsys.dev:9000"
    region                      = "us-east-1"
    skip_credentials_validation = true
    skip_region_validation      = true
    skip_metadata_api_check     = true
    force_path_style            = true
  }
}

provider "proxmox" {
  endpoint  = var.pve_api_endpoint
  api_token = var.pve_api_token
  insecure  = true  # Proxmox's default self-signed cert — TODO: switch to real cert via PVE's built-in ACME support
}