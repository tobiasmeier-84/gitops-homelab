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

## Running proxmox-auto-install-assistant on macOS

`proxmox-auto-install-assistant` is a Debian/Proxmox-packaged binary with no
macOS build — it must run inside a Linux environment. The simplest option is
a throwaway Docker container (requires Docker Desktop: `brew install --cask docker`):

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

Notes:
- `--platform=linux/amd64` is **required on Apple Silicon** — without it,
  Docker pulls the arm64 image by default, `apt-get update` succeeds but
  finds zero matching packages (Proxmox only publishes amd64), and you'll
  hit `E: Unable to locate package proxmox-auto-install-assistant`.
- The container mounts two host directories: the repo itself (`/work`) and
  `~/Downloads` (`/iso`) — keeps the multi-GB ISO out of the git repo
  entirely rather than requiring it to live inside the working directory.
  Adjust the `/iso/proxmox-ve_9.2-1.iso` filename to match whatever
  `ls ~/Downloads/proxmox-ve*.iso` actually shows — point-release version
  suffixes shift over time.
- Repeat the full command (fresh container each time) for `eros.toml` and
  `pallas.toml`, changing both the `--answer-file` and `--output` paths.
  Running one interactive shell (`docker run -it --rm --platform=linux/amd64
  -v "$(pwd):/work" -v "$HOME/Downloads:/iso" -w /work debian:trixie bash`)
  and running all three `prepare-iso` invocations inside it avoids
  reinstalling the package three times.

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