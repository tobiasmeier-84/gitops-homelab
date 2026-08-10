# Backlog

Every deliberately deferred item across this build, consolidated in one
place so it survives session/memory boundaries. Check this file before
considering the project "done" — nothing here blocks current progress,
but each item was a conscious trade-off worth revisiting eventually.

## Hardware

- **UPS automated graceful shutdown (NUT)** — UPS itself is in place;
  automatic graceful shutdown signaling to all 3 hosts on low battery is
  not yet configured. (Decision log, hardware layer)
- **10G NIC / switch redundancy** — hardware exists to support this
  (2x switches, dual-port card), not yet wired for redundancy.
  ([ADR-0009](adr/0009-nic-switch-redundancy-risk-accepted.md))
- **Possible 6th SATA SSD / 3rd NVMe upgrade** — mentioned as a
  possibility to check on, never confirmed either way. Worth a follow-up
  to see if it's feasible and whether it changes the storage layout.

## Network / Perimeter

- **RV320 firewall replacement** — EOL hardware at the internet-facing
  perimeter, risk knowingly accepted for now.
  ([ADR-0032](adr/0032-rv320-eol-risk-accepted.md))

## Identity / Access

- **SSH-to-Entra-ID** — key-based SSH access continues; centralized
  SSO/audit logging for SSH deferred until multiple admins or a real
  audit requirement exists.
  ([ADR-0020](adr/0020-ssh-entraid-backlogged.md))
- **Narrower custom Proxmox role for `terraform@pve`** — currently uses
  the broad `Administrator` role (required for `Sys.Modify`/disk
  operations, which `PVEAdmin` doesn't cover). A tighter custom role
  scoped to exactly what's needed is a reasonable hardening step, not
  yet done. (`opentofu/bootstrap-storage/README.md`)

## Secrets / State

- **OpenTofu native state encryption** — one of the two original reasons
  OpenTofu was chosen over Terraform, not yet actually enabled. State
  files (e.g. `bootstrap-minio`'s) currently contain some secrets in
  plaintext (the MinIO root password, for one) since `sensitive = true`
  only hides values from CLI output, not from the state file itself.
  ([ADR-0010](adr/0010-opentofu-over-terraform.md),
  [ADR-0036](adr/0036-state-bucket-backup.md))
- **`/etc/state-backup/rclone.conf` on `iapetus` holds B2 credentials in
  plaintext** — protected only by filesystem permissions (root-only,
  `chmod 600`), not encrypted at rest. Same underlying gap as state
  encryption above; worth solving together rather than separately.
  ([ADR-0036](adr/0036-state-bucket-backup.md))

## Reserved, not yet assigned

- **Earth / Mars naming space** — deliberately held in reserve with no
  assigned meaning, for a future use not yet identified (e.g. a genuine
  staging environment). ([ADR-0035](adr/0035-naming-convention.md))

  - **Proxmox Entra ID group-based authorization** — currently the admin
  user was granted `Administrator` directly
  (`pveum aclmod / -user <user>@entraid -role Administrator`), not via a
  group claim. Works, but doesn't scale — a second admin needs another
  manual grant rather than just joining a group. Proper fix: configure a
  groups claim in the Entra ID token, create a `pve-admins` security
  group, and map that group to the Proxmox role instead.
  ([ADR-0021](adr/0021-entraid-group-authorization-mapping.md),
  [ADR-0039](adr/0039-proxmox-entraid-oidc.md))

## IaC retrofit — manual steps to bring under OpenTofu management

Several early setup steps were done manually before we established the
discipline of checking provider schemas before building. Retrofit list,
worked through incrementally:

- [x] Cloudflare DNS records — imported into OpenTofu management
      (`opentofu/cloudflare/`)
- [x] Entra ID App Registration — imported (`opentofu/entraid/`); client
      secret itself remains unmanaged (can't be read back via API)
- [x] Backblaze B2 bucket — imported (`opentofu/backblaze/`)
- [ ] **Backblaze B2 application key management** — the
      `homelab-state-backup` key (in active use by `iapetus`'s backup
      script) is not managed by OpenTofu. Same reasoning as the Entra ID
      client secret: the actual secret value can't be read back via B2's
      API once created, only metadata. Could still manage the key's
      *shape* (capabilities, bucket restriction, name) via `b2_application_key`
      even without capturing the live secret — worth doing for
      documentation/drift-detection value, similar to the Entra ID
      secret-rotation follow-up.
- [ ] **Proxmox ACME config — check whether `bpg/proxmox` has native ACME
      resources** (the changelog references ACME-related attributes,
      never actually checked). Currently a manual `pveum`/SSH process
      documented in `proxmox-host/README.md`.
- [ ] Azure Key Vault — never actually built at all yet (ADR-0005 gap),
      automatable via `azurerm` provider

## Documentation updates needed after the IaC retrofit

As each manual setup step gets retrofitted into OpenTofu, the
**existing README documentation still describes the old manual process**
and needs updating to match — otherwise the docs actively mislead anyone
(including future us) trying to rebuild from scratch. Needs a pass over:

- `opentofu/cloudflare/README.md` — doesn't exist yet; needs writing to
  describe the actual DNS-record-import workflow
- `opentofu/entraid/README.md` — doesn't exist yet; needs writing
- `opentofu/backblaze/README.md` — doesn't exist yet; needs writing
- `opentofu/bootstrap-minio/README.md` — still describes manually
  creating the B2 bucket via the console; now contradicts the actual
  OpenTofu-managed process in `opentofu/backblaze/`
- `proxmox-host/README.md` — the Entra ID and ACME sections describe
  manual `az`/`pveum` steps; the Entra ID App Registration piece is now
  partially superseded by `opentofu/entraid/`

  - **`pallas`'s second 10G port (STORAGE) rejects its SFP+ module** —
  `ixgbe` driver explicitly refuses to initialize `01:00.1`:
  "failed to load because an unsupported SFP+ or QSFP module type was
  detected." Port `.0` (CLUSTER, working) uses a different, supported
  module. Fix: swap in a matching/genuine-Intel SFP+ transceiver
  (preferred), or override via `allow_unsupported_sfp=1` module parameter
  if a compatible module isn't available. **Blocks**: `pallas` can't
  fully join the STORAGE VLAN until resolved — must be fixed before
  Longhorn setup, since Longhorn needs STORAGE working identically on all
  3 nodes.