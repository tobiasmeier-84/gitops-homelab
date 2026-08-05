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