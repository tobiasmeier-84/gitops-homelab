# proxmox-network

Creates the 4 non-MGMT bridges (`vmbr1`-`vmbr4`) on all 3 Proxmox nodes,
per ADR-0031. MGMT (`vmbr0`) already exists via the answer-file install
and is untouched by this config.

## Design: plain bridges, not VLAN-aware

Each physical NIC connects to a switch port configured in **Access
mode** (single untagged VLAN) — confirmed directly via `display this` on
every relevant switch port. This means VLAN separation happens entirely
at the switch; the Proxmox-side bridges just need to be plain L2
bridges, structurally identical to `vmbr0`. No `vlan_aware`/`vids`
configuration needed.

## Port mapping (confirmed via MAC-address correlation across both
switches + `display this` on each port)

| Node | Bridge | Physical NIC | Switch | Port |
|---|---|---|---|---|
| ceres | vmbr1 (CLUSTER) | enp1s0f0 | medina | XGE1/0/26 |
| ceres | vmbr2 (STORAGE) | enp1s0f1 | anderson | XGE1/0/26 |
| ceres | vmbr3 (DMZ-INGRESS) | enp3s0 | medina | GE1/0/7 |
| ceres | vmbr4 (EGRESS) | enp4s0 | medina | GE1/0/6 |
| eros | vmbr1 (CLUSTER) | enp1s0f0 | medina | XGE1/0/27 |
| eros | vmbr2 (STORAGE) | enp1s0f1 | anderson | XGE1/0/27 |
| eros | vmbr3 (DMZ-INGRESS) | enp3s0 | medina | GE1/0/15 |
| eros | vmbr4 (EGRESS) | enp4s0 | medina | GE1/0/14 |
| pallas | vmbr1 (CLUSTER) | enp1s0f0 | medina | XGE1/0/28 |
| pallas | vmbr2 (STORAGE) | enp1s0f1 | anderson | XGE1/0/28 (pending) |
| pallas | vmbr3 (DMZ-INGRESS) | enp3s0 | medina | GE1/0/23 |
| pallas | vmbr4 (EGRESS) | enp4s0 | medina | GE1/0/22 |

## Known gap: pallas STORAGE

`pallas`'s `enp1s0f1` has a working physical link at the PCI/kernel
level, but the `ixgbe` driver rejects the SFP+ transceiver currently
installed:
ixgbe 0000:01:00.1: failed to load because an unsupported SFP+ or QSFP module type was detected.

The `vmbr2` bridge is created on `pallas` regardless — it will carry no
traffic until the transceiver is swapped for a supported/genuine module.
See `docs/BACKLOG.md`.

## Applying

```bash
source ~/homelab-env.sh
tofu init -backend-config="access_key=$MINIO_ROOT_USER" -backend-config="secret_key=$MINIO_ROOT_PASSWORD"
tofu plan
tofu apply
```

## Verifying

```bash
ssh root@ceres.belt.solsys.dev "ip link show | grep vmbr"
```
Should show `vmbr0` through `vmbr4`, all `UP` (except `pallas`'s `vmbr2`,
which will be up but carry no traffic until the SFP+ is fixed).