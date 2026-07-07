# ADR-0034: Greenfield full-cluster rebuild instead of rolling single-node migration

**Status:** Accepted

## Context
The original plan (see the original version of docs/runbooks/proxmox-node-reinstall.md) was a rolling, one-node-at-a-time Proxmox reinstall, preserving cluster quorum and keeping the existing HAProxy VM alive throughout via VRRP, on the assumption that HAProxy was load-bearing for production traffic to Nextcloud during the rebuild.

It was subsequently clarified that HAProxy currently only fronts the *old* Nextcloud instance, which runs on **separate bare-metal hardware**, entirely outside the 3-node Proxmox cluster. The Proxmox cluster itself (and the existing k3s study cluster running on it) is therefore not load-bearing for any production service.

## Decision
Temporarily repoint the RV320's NAT/port-forward rule directly at the bare-metal reverse proxy's IP, bypassing HAProxy/Proxmox entirely for the duration of the rebuild. Wipe and reinstall all 3 Proxmox nodes simultaneously (PVE 9.2, ZFS mirror, answer-file automation), form a brand-new Proxmox cluster from scratch, then repoint the RV320 back to the new HAProxy VIP once it's rebuilt.

## Reasoning
Removes the single biggest constraint the original rolling-migration plan was designed around (never losing quorum, keeping a VM alive throughout a multi-hour, multi-node process) for a constraint that turned out not to actually exist. A simultaneous greenfield rebuild is faster, simpler, and has fewer intermediate states to reason about or get wrong.

## Consequences
- The existing k3s study cluster is destroyed with no preservation path — explicitly accepted as a desired clean slate, not an accidental loss.
- There is no existing Proxmox cluster membership to preserve; the new cluster is formed via `pvecm create`/`pvecm add` rather than `pvecm delnode`/rejoin.
- The rolling, one-node-at-a-time procedure (originally documented in full) remains valuable for **future** maintenance once the new cluster is actually in production use and losing quorum genuinely matters again — retained in the runbook as a separate procedure, not deleted.