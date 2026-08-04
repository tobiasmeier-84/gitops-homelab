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

  # Local state deliberately, for this bootstrap config specifically —
  # this runs before the self-hosted state backend (ADR-0024) exists.
  # State file must never be committed — see repo .gitignore.
}

provider "proxmox" {
  endpoint  = var.pve_api_endpoint
  api_token = var.pve_api_token
  insecure  = true  # Proxmox's default self-signed cert — TODO: switch to real cert via PVE's built-in ACME support
}