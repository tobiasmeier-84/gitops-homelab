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

- [x] **RESOLVED** — Proxmox Entra ID group-based authorization implemented
      via App Roles + `proxmox_realm_openid`/`proxmox_virtual_environment_group`/
      `proxmox_acl`, fully OpenTofu-managed. Old direct per-user grant
      removed and confirmed unnecessary via a clean logout/login test.
      See [ADR-0042](adr/0042-cross-service-rbac.md).

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

- **`pallas`'s STORAGE port (`enp1s0f1`/`anderson` XGE1/0/28) had a
  defective/mismatched transceiver** — reported `Vendor Name: HPE` with
  no `Ordering Name` (unlike 3 other working HPE modules on the same
  switch, which all show one) and an unusually short reported distance
  (0.51m vs. the expected several meters). Root cause was a bad/wrong
  individual unit, not a vendor or driver compatibility issue — 3
  different vendors (TE Connectivity, generic OEM `SFP-10G-CU1M`, HPE
  JD09X-series) all confirmed working elsewhere on identical hardware.
  **Fix in progress**: replacement `SFP-10G-CU1M`-style DAC ordered,
  expected within ~2 days. Once installed:
  1. Verify link: `ethtool -m enp1s0f1` on `pallas`, `display transceiver
     interface te 1/0/28` on `anderson`
  2. Set jumbo-frame MTU: `pvesh set /nodes/pallas/network/enp1s0f1
     --type eth --mtu 9000` then `pvesh set /nodes/pallas/network`
  3. In `opentofu/proxmox-network/main.tf`: remove the `pallas`
     exclusion from `node_bridge_pairs` and add `pallas` back to
     `null_resource.storage_interface_mtu`'s `for_each`
  4. `tofu plan` / `tofu apply`

- [x] **RESOLVED** — `pallas`'s STORAGE port had a defective transceiver
    (blank Ordering Name, non-standard reported distance). Replaced
    with a genuine Intel-branded DAC (`821-24-071-02`), confirmed
    working via kernel probe, switch MAC table, and live traffic.
    `vmbr2`/MTU 9000/`rhea`'s STORAGE NIC all completed.

- **Proxmox VE / Debian host CIS hardening** — no official CIS benchmark
  exists for Proxmox VE itself (confirmed via Proxmox's own community
  forum). Community consensus is to extend the CIS Debian Linux
  Benchmark with Proxmox-specific additions, but multiple sources warn
  this risks breaking cluster communication (corosync/pmxcfs) or ZFS
  functionality if applied without careful, tested adaptation — several
  community-maintained guides explicitly flag controls as "not yet
  validated." Needs a dedicated, carefully-tested effort, not a quick
  script run. The Debian-based VM guests (RKE2 nodes, HAProxy trio) are
  a safer, more direct fit for the standard CIS Debian Benchmark, since
  they carry no Proxmox-specific services.
- **FIPS 140 applicability** — not researched in depth. Debian mainline's
  FIPS tooling maturity is unclear (unlike RHEL's first-class "FIPS
  mode"). Typically a compliance requirement for regulated/government
  environments; unclear whether it's relevant to this project's actual
  goals. Needs proper research before any decision, not a shallow
  answer.

- **`external-dns`** — DNS records for new apps are currently added
  manually via `opentofu/cloudflare/` (one commit per app). Genuinely
  tied to completing the Crew tenant self-service story (ADR-0042/0043)
  — a tenant deploying their own app via their own git repo shouldn't
  need the platform owner to manually add a DNS record every time.
  `external-dns` watches Ingress resources and creates/updates Cloudflare
  records automatically. Worth its own deliberate setup, not bundled
  into a smaller task.

- **ZTNA for admin-plane interfaces (Proxmox, and future Harbor/Grafana
  admin UIs)** — only reachable from internal VLANs today; a demo/recruiter
  identity can't log in remotely without VPN. Direct port-forwarding
  rejected (hypervisor management planes shouldn't be internet-facing
  regardless of account scoping). Candidates, not yet decided:
  Cloudflare Access (free tier, proprietary, reuses existing Cloudflare
  setup + Entra ID), Pomerium (open source, self-hosted, native OIDC),
  Pangolin (open source, newer, Cloudflare-Tunnel-alternative — maturity
  unconfirmed). Decide when actually prioritized.

- **`external-dns`** — **priority raised**: no longer just convenience,
  now a genuine blocker for full self-service (see the tenant
  onboarding runbook, `docs/runbooks/tenant-onboarding.md`, and
  ADR-0046). Without it, every new tenant hostname needs a manual
  OpenTofu commit to `opentofu/cloudflare/`, breaking the "deploy via
  git alone" promise for the DNS piece specifically. Watches Ingress
  resources, creates/updates Cloudflare records automatically.