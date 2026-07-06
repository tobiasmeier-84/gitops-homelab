# Terraform

Provisions the Proxmox VMs for the RKE2 cluster (`environments/prod/`), using the reusable `modules/proxmox-vm/` module. Uses the `bpg/proxmox` provider.

State is not committed to this repo — see `.gitignore`. A remote backend (e.g. a self-hosted MinIO/S3-compatible target) is recommended; documented here once configured.
