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
sops -d proxmox-host/secrets/root-password.enc.yaml > /tmp/root-password.plain.yaml
python3 proxmox-host/render.py /tmp/root-password.plain.yaml
rm /tmp/root-password.plain.yaml
```

This writes `rendered/ceres.toml`, `rendered/eros.toml`, `rendered/pallas.toml`
— never committed (see repo `.gitignore`), since each embeds a password hash.

## Determining disk and NIC values — do this in the actual install boot session

Both the disk and network filters need values gathered from the **exact same
boot session** as the install itself — not a prior live-boot check — since
this is what makes bare disk names like `sda`/`sdb` safe to use despite
normally being considered unstable.

**Disks**: from the installer's debug shell (`Ctrl+Alt+F2` or `F3`):
```bash
ls -l /dev/disk/by-id/ | grep <model-number-or-known-identifier>
```
This maps each disk's stable serial-based identifier to its current `sdX`
name for this boot. Use the `sdX` names (not the full `by-id` path) in
`nodes.yaml`.

**Network**: from the same shell:
```bash
udevadm info /sys/class/net/eno1 | grep ID_NET_NAME_MAC
```
Use the full value after the `=` (e.g. `enx9c8e994fac0e`) — not the plain
interface name.

**Alternative if you want zero ambiguity**: physically disconnect every disk
except the 2 intended for the boot mirror before starting the install. With
only `sda`/`sdb` present, there's no possible confusion — reconnect the rest
once the OS install completes (they aren't needed until the Longhorn setup
step, much later).

## Validating the answer file — always do this before building an ISO

```bash
docker run -it --rm --platform=linux/amd64 \
  -v "$(pwd):/work" \
  -w /work debian:trixie bash -c '
  apt-get update && apt-get install -y wget
  mkdir -p /usr/share/keyrings
  wget https://enterprise.proxmox.com/debian/proxmox-archive-keyring-trixie.gpg \
    -O /usr/share/keyrings/proxmox-archive-keyring.gpg
  echo "Types: deb
URIs: http://download.proxmox.com/debian/pve
Suites: trixie
Components: pve-no-subscription
Signed-By: /usr/share/keyrings/proxmox-archive-keyring.gpg" > /etc/apt/sources.list.d/pve-install-repo.sources
  apt-get update
  apt-get install -y proxmox-auto-install-assistant
  proxmox-auto-install-assistant validate-answer /work/proxmox-host/rendered/ceres.toml
'
```

**Important**: `validate-answer` only checks TOML syntax and schema shape —
it cannot confirm that disk/NIC values actually exist on real hardware. A
clean pass here does not guarantee the install will find matching devices;
it only rules out structural/syntax mistakes (see Troubleshooting below for
the class of error this doesn't catch).

## Building the bootable ISO (per node)

```bash
docker run -it --rm --platform=linux/amd64 \
  -v "$(pwd):/work" \
  -v "$HOME/Downloads:/iso" \
  -w /work debian:trixie bash -c '
  apt-get update && apt-get install -y wget
  mkdir -p /usr/share/keyrings
  wget https://enterprise.proxmox.com/debian/proxmox-archive-keyring-trixie.gpg \
    -O /usr/share/keyrings/proxmox-archive-keyring.gpg
  echo "Types: deb
URIs: http://download.proxmox.com/debian/pve
Suites: trixie
Components: pve-no-subscription
Signed-By: /usr/share/keyrings/proxmox-archive-keyring.gpg" > /etc/apt/sources.list.d/pve-install-repo.sources
  apt-get update
  apt-get install -y proxmox-auto-install-assistant
  proxmox-auto-install-assistant prepare-iso /iso/proxmox-ve_9.2-1.iso \
    --fetch-from iso \
    --answer-file /work/proxmox-host/rendered/ceres.toml \
    --output /work/ceres-auto.iso
'
```

Reflash the USB with the resulting ISO:
```bash
diskutil list
diskutil unmountDisk /dev/disk4
sudo dd if=ceres-auto.iso of=/dev/rdisk4 bs=4m
```
Repeat for `eros` and `pallas` with their respective rendered files.

## Troubleshooting

**"No disks found matching selection"** — the `disk-list`/`filter` values
don't match any real device. Common causes, in order of likelihood:
- Values were captured in a *different* boot session than the one failing
  (kernel disk enumeration/naming can shift between boots).
- SATA controller is in RAID/RST mode rather than AHCI (common on HP
  business desktops) — disks won't expose standard `by-id` nodes at all in
  this mode. Check BIOS (commonly Advanced → SATA Configuration) and switch
  to AHCI.
- Values were copied from a different node's `nodes.yaml` entry by mistake.

**`filter.X = [...]` fails with "invalid type: sequence, expected a string"**
— `filter` properties only accept a single string value each, never an
array, regardless of the property. To match multiple specific disks, use
`disk-list` instead (bare names like `"sda"`, `"sdb"`), not `filter`.

**`filter.ID_NET_NAME` doesn't work** — this isn't a real udev property.
Use `filter.ID_NET_NAME_MAC` (most stable — tied to the physical NIC, not
its PCI slot or onboard position) instead.

**Before assuming a value is wrong, verify what the installer will actually
match**, directly on the real hardware:
```bash
proxmox-auto-install-assistant device-match disk ID_SERIAL='...'
proxmox-auto-install-assistant device-match network ID_NET_NAME_MAC='...'
```
An empty result confirms a mismatch before you burn another build/reflash
cycle.

## What this does *not* configure

The answer file's `[network]` section sets up exactly one interface: MGMT
(10.10.10.0/24), enough to get the hypervisor installed and reachable via
SSH/Ansible. The full VLAN-aware network configuration (bridges and tagged
interfaces for CLUSTER, STORAGE, DMZ-INGRESS, EGRESS — see
[ADR-0031](../docs/adr/0031-vlan-network-segmentation.md)) is applied
afterward by Ansible's `common` role, not by this answer file.