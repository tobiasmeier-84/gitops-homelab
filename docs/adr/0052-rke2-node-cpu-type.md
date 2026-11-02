# ADR-0052: RKE2 node VMs use the x86-64-v2-AES CPU type

**Status:** Accepted - rollout in progress (started 2026-11-02)

## Context
The `proxmox-vm` module never set a CPU type, so the provider default
`qemu64` applied to every VM. Inside the three RKE2 nodes (`enceladus`,
`mimas`, `rhea`) the guest reports "QEMU Virtual CPU version 2.5+": a
minimal baseline model without SSSE3, SSE4.1/4.2 and POPCNT. Container
images and language runtimes are increasingly built for the x86-64-v2
baseline; on a qemu64 guest such binaries can crash with
illegal-instruction errors or silently fall back to slower code paths.
The physical hosts (`ceres`, `eros`, `pallas`) support far more than the
guests were allowed to see.

## Decision
- The three RKE2 node VMs use CPU type `x86-64-v2-AES`, the baseline that
  Proxmox and the bpg/proxmox provider documentation recommend.
- `proxmox-vm` gets a variable `cpu_type` (default `qemu64`, i.e. the
  previous behaviour, so the HAProxy trio, `deimos`, the DNS pair and
  `iapetus` are unchanged). `environments/prod` passes `x86-64-v2-AES`
  for the three nodes.
- Not `host`: it exposes the exact host CPU model and would block moving
  a VM between hosts with different CPUs, with no benefit for these
  workloads.
- Not `x86-64-v3`: needs AVX2/BMI2 on every host and nothing here
  requires it.
- Existing VMs are changed live, not through OpenTofu. The module's
  `lifecycle { ignore_changes = all }` guard (2026-10-23) stays, so
  `tofu plan` shows no change for them; the value in code documents the
  intended state and applies to future rebuilds.

## Rollout procedure (one node at a time: enceladus, mimas, rhea last)
1. Check that the Proxmox hosts report ssse3, sse4_2, popcnt and aes in
   `/proc/cpuinfo`, all nodes are Ready, all Longhorn volumes are healthy
   and no backup prepare/upload is running.
2. `kubectl cordon` and `kubectl drain --ignore-daemonsets
   --delete-emptydir-data` the node.
3. On its Proxmox host: `qm shutdown <vmid>`, `qm set <vmid> --cpu
   x86-64-v2-AES`, `qm start <vmid>`. A reboot inside the guest does not
   apply a CPU type change; a full stop/start is required.
4. Wait until the node is Ready, `kubectl uncordon`, wait until all
   Longhorn volumes are healthy again.
5. Verify in the guest that `/proc/cpuinfo` shows ssse3, sse4_2 and
   popcnt, then continue with the next node.

## Consequences
- Each node restarts once and its pods move to the other two. etcd keeps
  quorum because only one of the three RKE2 servers is down at a time.
- `rhea` goes last: it holds Plex and the backup staging volume.
- Longhorn replicas, etcd data and the passed-through disks are untouched.
- Rollback per node: `qm set <vmid> --cpu qemu64` plus a full stop/start.
