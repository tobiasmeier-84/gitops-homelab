# ADR-0002: Storage — Longhorn over Ceph

**Status:** Accepted

## Context
No existing Ceph deployment; explicitly ruled out on this hardware for performance reasons.

## Decision
Longhorn, using a dedicated disk per node passed into each VM (not the OS disk).

## Reasoning
Running Ceph underneath Proxmox and a second replication layer (e.g. Longhorn or another CSI) on top would double replication overhead for no benefit. Longhorn alone, with genuinely independent per-node physical disks (not a shared datastore), gives real redundancy without operating two storage systems.

## Consequences
Replica count set to 3 (matches node count). Usable capacity per volume equals the physical disk size, not disk size × replica count. Longhorn's replication traffic is placed on the 10G link to avoid contending with other traffic.
