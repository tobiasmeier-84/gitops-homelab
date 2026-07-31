# bootstrap-storage

Creates the storage pools on all 3 Proxmox nodes, using OpenTofu natively:
- **`razorback`** — NVMe #1, single disk, general fast tier (RKE2 VM
  root/etcd) — named for Bobbie's racing pinnace
- **`tachi`** — NVMe #2, single disk, dedicated fast tier for Nextcloud's
  database volume specifically (named for Rocinante's original name — tied
  to the workload this pool serves)
- **`canterbury`** — the 3 remaining SATA SSDs, striped/non-redundant
  (Longhorn already provides cross-node redundancy on top, so a second
  redundancy layer here would just waste capacity) — named for the ice
  hauler, fitting for bulk cargo storage

**Runs before the main `environments/prod` OpenTofu config** — VM
provisioning there references these pool IDs for disk placement, so they
must exist first. Same bootstrapping-order pattern as the state backend
(ADR-0024): this config uses **local state**, deliberately, since it runs
before any shared backend exists.

## ⚠️ Before running: verify the resource schema

`proxmox_virtual_environment_node_disk_zfs` was added to the `bpg/proxmox`
provider very recently (v0.111.0, June 2026). The argument names in
`main.tf` are a best-effort draft, not confirmed against full provider
documentation. Before `tofu apply`:

```bash
tofu providers schema -json | jq '.provider_schemas."registry.opentofu.org/bpg/proxmox".resource_schemas.proxmox_virtual_environment_node_disk_zfs'
```

Check specifically:
- The exact `raid_level` value meaning "striped, no redundancy" (used for `canterbury`)
- Whether `devices` expects `/dev/disk/by-id/...` paths or bare device names
  (given the answer-file `disk-list` vs `filter` lesson learned earlier,
  don't assume — confirm)

Safe way to test without risking real infrastructure: run `tofu plan`
(never `apply`) after filling in `terraform.tfvars` — if the format is
wrong, `plan` will surface it before anything is actually created.

## One-time setup

1. Create a dedicated, least-privilege Proxmox user + API token for OpenTofu
   (don't reuse root):
```bash
   pveum user add terraform@pve
   pveum aclmod / -user terraform@pve -role PVEAdmin   # or a narrower custom role
   pveum user token add terraform@pve bootstrap
```
   Save the resulting token — it's shown only once.

2. Store it encrypted:
```bash
   sops secrets/pve-api-token.enc.yaml
   # paste: pve_api_token: "terraform@pve!bootstrap=<uuid-from-above>"
```

3. Determine the real disk identifiers per node — **NVMe #1** (`razorback`),
   **NVMe #2** (`tachi`), and the 3 remaining SATA SSDs (`canterbury`):
```bash
   ls -l /dev/disk/by-id/ | grep -v part
```
   Fill in `terraform.tfvars` (copied from the `.example`) and **commit it**
   — not a secret, hardware config only.

## Applying

```bash
sops -d secrets/pve-api-token.enc.yaml > /tmp/pve-token.yaml
export TF_VAR_pve_api_token=$(grep pve_api_token /tmp/pve-token.yaml | cut -d'"' -f2)
rm /tmp/pve-token.yaml

export TF_VAR_pve_api_endpoint="https://ceres.belt.solsys.dev:8006/"

tofu init
tofu plan
tofu apply
```

## After applying

Confirm on any node:
```bash
pvesm status
```
Should show `razorback`, `tachi`, and `canterbury` alongside the default boot pool.