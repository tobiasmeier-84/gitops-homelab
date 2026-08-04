terraform {
  required_version = ">= 1.7.0"  # OpenTofu

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = ">= 0.111.0"
    }
  }

  # Local state deliberately — this creates the remote state backend
  # itself, so it can't depend on that backend existing yet. See ADR-0024.
}

provider "proxmox" {
  endpoint  = var.pve_api_endpoint
  api_token = var.pve_api_token
  insecure  = true  # Proxmox's default self-signed cert — same accepted trade-off as bootstrap-storage

  ssh {
    agent    = true
    username = "root"
  }
}