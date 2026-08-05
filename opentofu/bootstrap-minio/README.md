# bootstrap-minio

Provisions `iapetus` — a small VM running MinIO, providing the self-hosted,
S3-compatible remote state backend called for in ADR-0024.

**Uses local state, deliberately** — this creates the remote backend
itself, so it can't depend on that backend existing yet. Same pattern as
`bootstrap-storage`.

- Node: `ceres` | Storage: `canterbury` | 2 vCPU / 2GB RAM / 40GB disk
- MGMT-VLAN IP: `10.10.10.24` (`iapetus.orbit.solsys.dev`)

## ⚠️ Before applying: verify against live schema

Unlike `proxmox_node_disk_zfs`, `proxmox_virtual_environment_vm` is a
well-established, documented resource — but the exact attribute names in
`main.tf` are still a best-effort draft, not confirmed against the live
schema. Before `tofu apply`:

​```bash
tofu providers schema -json | jq '.provider_schemas["registry.opentofu.org/bpg/proxmox"].resource_schemas["proxmox_virtual_environment_vm"]' > /tmp/vm-schema.json
​```

Check specifically against `/tmp/vm-schema.json`:
- `network_device.bridge` — confirm the actual bridge name for MGMT on `ceres`
- `disk.datastore_id` / `disk.interface` — confirm these are the correct nested attribute names
- `proxmox_virtual_environment_file` — confirm `datastore_id = "local"` is correct for snippet storage (cloud-init files typically need directory-type storage, not a zfspool)

Use `tofu plan` (never `apply`) to safely surface any mismatches first.

## Prerequisites

1. **VM admin SSH key** (separate from the Proxmox host key):
   ​```bash
   ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519_vms -C "admin@homelab-vms"
   ​```
   Store the private half in KeePass. The public half goes in `terraform.tfvars`.

2. **MinIO credentials**:
   ​```bash
   sops secrets/minio-credentials.enc.yaml
   ​```

3. **`terraform.tfvars`** (commit once filled in):
   ​```hcl
   vm_ssh_public_key = "ssh-ed25519 AAAA... admin@homelab-vms"
   ​```

## Applying

​```bash
sops -d secrets/minio-credentials.enc.yaml > /tmp/minio-creds.yaml
export TF_VAR_minio_root_user=$(grep minio_root_user /tmp/minio-creds.yaml | cut -d'"' -f2)
export TF_VAR_minio_root_password=$(grep minio_root_password /tmp/minio-creds.yaml | cut -d'"' -f2)
rm /tmp/minio-creds.yaml

export TF_VAR_pve_api_endpoint="https://ceres.belt.solsys.dev:8006/"

tofu init
tofu plan
tofu apply
​```

## After applying

1. Confirm MinIO is reachable:
   ​```bash
   curl https://iapetus.orbit.solsys.dev:9000/minio/health/live
   ​```
2. Create the state bucket:
   ​```bash
   brew install minio-mc
   mc alias set homelab https://iapetus.orbit.solsys.dev:9000 <root_user> <root_password>
   mc mb homelab/opentofu-state
   ​```

## Migrating bootstrap-storage and future configs onto this backend

Add to `bootstrap-storage/versions.tf`'s `terraform` block:
​```hcl
backend "s3" {
  bucket                      = "opentofu-state"
  key                         = "bootstrap-storage/terraform.tfstate"
  endpoint                    = "https://iapetus.orbit.solsys.dev:9000"
  region                      = "us-east-1"
  access_key                  = "<root_user>"
  secret_key                  = "<root_password>"
  skip_credentials_validation = true
  skip_region_validation      = true
  skip_metadata_api_check     = true
  force_path_style            = true
}
​```
Then:
​```bash
tofu init -migrate-state
​```

**Note**: hardcoding credentials in a committed backend block isn't ideal —
OpenTofu's native state encryption is the better long-term answer. Treat
this as a working first pass, encrypted backend credentials as a follow-up.

## Gotchas discovered building this

- **Provider auth vs. SSH auth are separate.** The API token handles most
  operations, but file uploads (snippets, cloud-init) go through the
  provider's *internal SSH client* instead — needs its own `ssh { agent =
  true; username = "root" }` block in the provider config.

- **`local` storage needs `snippets` and `import` content types enabled**
  before cloud-init file uploads or cloud-image downloads will work:
```bash
  pvesm set local --content iso,vztmpl,backup,snippets,import
```

- **A VM's disk is empty by default.** Cloud-init only *configures* an OS,
  it doesn't install one — need `proxmox_download_file` to pull a cloud
  image, then reference it via the disk block's `import_from`.

- **`import_from` only applies at VM creation, not on update** — if you set
  it on an already-created VM, OpenTofu updates its own state but the
  actual disk is untouched. Fix: `tofu apply -replace="<resource>"` to
  force genuine recreation.

- **`network_device` is a nested attribute, not a block** — needs
  list-of-object syntax (`network_device = [{ ... }]`) with *every* field
  present (`null` for ones you don't set).

- **SOPS secret extraction**: use `yq '.key' file.yaml`, not
  `grep key file.yaml | cut -d'"' -f2` — `cut` silently breaks if the YAML
  values aren't wrapped in quotes exactly as expected.

- **`qm cloudinit dump` can show stale/misleading content** even when
  `cicustom` correctly references the right file — check the actual file
  on disk (`cat /var/lib/vz/snippets/<file>`) instead of trusting this
  command if something looks wrong.

- **A `qm reset` isn't always enough to force cloud-init to re-run** —
  use a full `qm stop` + `qm start` cycle when troubleshooting cloud-init
  not applying correctly.

- **`qm terminal` needs a serial device configured** (`qm set <id>
  -serial0 socket`) and a real allocated TTY (`ssh -t ...`, not plain
  `ssh ...`) — otherwise it fails outright or misbehaves.

- **Keep track of which SSH key is authorized where** — this build uses
  3 separate keys (GitHub, Proxmox host root access, VM admin access).
  `ssh-add -l` before troubleshooting a "permission denied" is often
  faster than assuming something's actually broken.

  ## State bucket backup (ADR-0036)

A systemd timer on `iapetus` itself backs up the OpenTofu state bucket
daily to Backblaze B2 — simple, single-copy, not the full dual-chain design
used for application data (ADR-0005).

### Prerequisites

1. Dedicated age keypair:
   ​```bash
   age-keygen -o ~/state-backup-age-key.txt
   ​```
   Private key → KeePass. Public key → `terraform.tfvars` as
   `state_backup_age_public_key` (fine to commit, not secret).

2. Backblaze B2 credentials (Application Key scoped to a dedicated bucket
   `homelab-opentofu-state-backup`):
   ​```bash
   sops secrets/state-backup-credentials.enc.yaml
   ​```

### Applying

​```bash
sops -d secrets/state-backup-credentials.enc.yaml > /tmp/b2-creds.yaml
export TF_VAR_b2_key_id=$(yq '.b2_key_id' /tmp/b2-creds.yaml)
export TF_VAR_b2_application_key=$(yq '.b2_application_key' /tmp/b2-creds.yaml)
rm /tmp/b2-creds.yaml

tofu plan
tofu apply
​```

### Verifying

​```bash
ssh admin@iapetus.orbit.solsys.dev "sudo systemctl status state-backup.timer"
ssh admin@iapetus.orbit.solsys.dev "sudo systemctl start state-backup.service"
ssh admin@iapetus.orbit.solsys.dev "sudo journalctl -u state-backup.service -n 50"
​```

### Restoring, if ever needed

​```bash
rclone copy b2-state-backup:homelab-opentofu-state-backup/<file>.tar.zst.age .
age -d -i ~/state-backup-age-key.txt -o restored.tar.zst <file>.tar.zst.age
zstd -d restored.tar.zst -o restored.tar
tar -xf restored.tar
mc mirror ./opentofu-state homelab/opentofu-state
​```