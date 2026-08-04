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

## Why canterbury uses a provisioner instead of proxmox_node_disk_zfs

Proxmox's own ZFS-creation API validates that `raidlevel = "single"` must
have exactly 1 disk — it has no built-in option for a plain multi-disk
stripe with zero redundancy. Since Longhorn already provides redundancy at
the cluster level (ADR-0002), and this design deliberately avoids paying
for host-level redundancy Longhorn makes unnecessary, `canterbury` is
created via a raw `zpool create` over SSH (a `null_resource` +
`remote-exec` provisioner) instead.

**Requires a local ssh-agent with a key authorized for root on all 3
nodes** — the same KeePassXC-backed SSH key setup already used for manual
administration. Run `ssh-add -l` to confirm your agent has a key loaded
before `tofu apply`.

**Known limitation**: `tofu destroy` will not automatically tear down this
raw zpool (no destroy-time provisioner is configured) — manual cleanup via
`zpool destroy canterbury` on each node is required if this pool is ever
meant to be fully removed, not just recreated.

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

## Prerequisite: SSH key for the canterbury provisioner

The `null_resource.canterbury_zpool` provisioner connects to each node over
SSH as `root` — this requires **key-based authentication already set up**
before `tofu apply` runs. Without it, the provisioner hangs indefinitely
retrying a connection it can never complete (password auth can't be
answered interactively by OpenTofu), rather than failing with a clear error.

### One-time setup

1. Generate a dedicated key for this purpose — separate from your GitHub
   key, since this is root access to physical infrastructure, a different
   trust domain entirely:
```bash
   ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519_pve -C "terraform-root@proxmox-nodes"
```

2. Copy the public key to each node's root account (uses password auth one
   last time — the plaintext root password set during the answer-file setup,
   e.g. from KeePass):
```bash
   ssh-copy-id -i ~/.ssh/id_ed25519_pve.pub root@ceres.belt.solsys.dev
   ssh-copy-id -i ~/.ssh/id_ed25519_pve.pub root@eros.belt.solsys.dev
   ssh-copy-id -i ~/.ssh/id_ed25519_pve.pub root@pallas.belt.solsys.dev
```

3. Load it into your agent and confirm:
```bash
   ssh-add ~/.ssh/id_ed25519_pve
   ssh-add -l
```

4. Verify key-based auth works **before** involving OpenTofu at all:
```bash
   ssh root@ceres.belt.solsys.dev "echo connected"
```
   Should return instantly, no password prompt. If this hangs or prompts
   for a password, fix that first — `tofu apply` will have the identical
   problem, just less obviously.

5. Store the private key (`~/.ssh/id_ed25519_pve`) in your password manager
   (KeePass), same as the GitHub and age keys — arguably the most sensitive
   credential in this entire build, given it's root access to the physical
   hosts.

### If `tofu apply` hangs anyway

Confirm `ssh-add -l` still shows the key loaded (agents don't always persist
keys across every new terminal session/reboot) before assuming something
else is wrong.

## One-time setup

1. Create a dedicated Proxmox user + API token for OpenTofu. **Note:**
   `Sys.Modify` (required for ZFS/disk management) is not included in the
   `PVEAdmin` role — this needs the full `Administrator` role instead, on
   **both** the user and the token (a token's effective permissions can
   never exceed its owning user's, regardless of the token's own ACL):
```bash
   pveum user add terraform@pve
   pveum aclmod / -user terraform@pve -role Administrator
   pveum user token add terraform@pve bootstrap --privsep 0
   pveum aclmod / -token 'terraform@pve!bootstrap' -role Administrator
```
   Verify privilege separation actually took effect (this has silently
   failed before — worth checking rather than assuming):
```bash
   pveum user token list terraform@pve
```
   The `privsep` column should show `0`. If it shows `1`, the token has no
   permissions of its own regardless of the user's role — either recreate
   it with `--privsep 0`, or explicitly grant the token role as shown above.

   **Trade-off worth knowing**: this grants a fairly broad `Administrator`
   role to a service account, wider than the originally intended narrow
   scope, purely to satisfy one operation (`Sys.Modify` for disk creation).
   A tighter custom role (`pveum role add`) scoped to exactly what's needed
   is a reasonable hardening step later, not required to get started.

   This prints the token's secret value **once, only** — copy it
   immediately. Assemble the value needed for `pve_api_token` as
   `<full-tokenid>=<value>`, e.g.
   `terraform@pve!bootstrap=12345678-abcd-1234-abcd-1234567890ab`.

   **Shell gotcha**: the `!` in the token ID triggers history expansion in
   bash/zsh if typed directly into an interactive terminal. Run `set +H` to
   disable this for the session, or wrap the value in single quotes.

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