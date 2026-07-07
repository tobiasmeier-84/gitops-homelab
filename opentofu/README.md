# OpenTofu

Provisions the Proxmox VMs for the RKE2 cluster (`environments/prod/`), using the reusable `modules/proxmox-vm/` module. Uses the `bpg/proxmox` provider.

State is not committed to this repo — see `.gitignore`. Remote state is hosted on a self-hosted MinIO instance, bootstrapped separately (local state, minimal footprint) before the main OpenTofu configuration runs against it — see ADR-0024 and the bootstrap-ordering runbook (ADR-0025, `docs/runbooks/`).
