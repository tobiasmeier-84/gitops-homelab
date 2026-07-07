# ADR-0015: OS patch/reboot orchestration — Kured over unattended-upgrades alone

**Status:** Accepted

## Context
Security/kernel updates on the RKE2 nodes periodically require a reboot. `unattended-upgrades` (Debian's own automatic patching tool) can apply updates and reboot automatically, but has no awareness of Kubernetes scheduling.

## Decision
Kured, layered on top of unattended-upgrades.

## Reasoning
Kured watches for a pending-reboot marker (left by unattended-upgrades) and only then cordons the node, drains its pods to the other two nodes, reboots, and uncordons — one node at a time, cluster-aware. Plain unattended-upgrades alone would reboot a node the moment it decides to, with no coordination with the scheduler, risking simultaneous multi-node reboots or reboots during active workload placement.

## Consequences
One more controller running in the cluster, but the alternative (uncoordinated reboots on a 3-node cluster where quorum is already thin) is a meaningfully worse failure mode.
