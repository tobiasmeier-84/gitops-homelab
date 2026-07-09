# proxmox-host

Automated, unattended Proxmox VE installation via answer files — see
[ADR-0025](../docs/adr/0025-bootstrap-ordering-runbook.md) for where this
fits in the overall bootstrap sequence (this is step one).

## Files

- `answer.toml.j2` — the answer-file template (ZFS RAID1 boot mirror,
  static MGMT-VLAN IP, no DHCP — see ADR-0031)
- `nodes.yaml` — per-node values (hostname, MGMT IP, NIC name, boot disks).
  **Contains placeholders — must be filled in with real hardware values
  before rendering.**
- `secrets/root-password.enc.yaml` — SOPS-encrypted root password hash
  (not committed until created; see `secrets/root-password.enc.yaml.example`
  for the expected shape)
- `render.py` — merges the template + nodes.yaml + decrypted password hash
  into one `.toml` file per node, written to `rendered/` (gitignored)

## One-time setup

1. Determine the real per-node values for `nodes.yaml`:
   - **NIC name**: boot a live Linux environment on the physical host and
     run `ip link` — find the onboard 1G NIC's persistent name (commonly
     `eno1` on this hardware class, but verify, don't assume).
   - **Boot disks**: run `lsblk -d -o NAME,SIZE,MODEL,SERIAL` and pick 2 of
     the 5 SATA SSDs. Use `/dev/disk/by-id/...` paths (stable across
     reboots), not `/dev/sda`-style names.
   - Replace every `REPLACE_ME_...` placeholder in `nodes.yaml` accordingly.

2. Generate the root password hash and store it encrypted:
```bash
   openssl passwd -6                      # prompts for password, prints a $6$... hash
   sops secrets/root-password.enc.yaml    # paste: root_password_hash: "$6$..."
```

## Rendering the per-node answer files

```bash
pip install jinja2 pyyaml
sops -d secrets/root-password.enc.yaml > /tmp/root-password.plain.yaml
python3 render.py /tmp/root-password.plain.yaml
rm /tmp/root-password.plain.yaml
```

This writes `rendered/ceres.toml`, `rendered/eros.toml`, `rendered/pallas.toml`
— never committed (see repo `.gitignore`), since each embeds a password hash.

## Validating and building the bootable ISO (per node)

​```bash
proxmox-auto-install-assistant validate rendered/ceres.toml

proxmox-auto-install-assistant prepare-iso proxmox-ve_9.2-1.iso \
  --fetch-from iso \
  --answer-file rendered/ceres.toml \
  --output ceres-auto.iso
​```

Repeat for `eros` and `pallas` with their respective rendered files.

## What this does *not* configure

The answer file's `[network]` section sets up exactly one interface: MGMT
(10.10.10.0/24), enough to get the hypervisor installed and reachable via
SSH/Ansible. The full VLAN-aware network configuration (bridges and tagged
interfaces for CLUSTER, STORAGE, DMZ-INGRESS, EGRESS — see
[ADR-0031](../docs/adr/0031-vlan-network-segmentation.md)) is applied
afterward by Ansible's `common` role, not by this answer file.