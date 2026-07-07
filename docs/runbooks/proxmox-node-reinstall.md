# Runbook: Proxmox cluster rebuild

Two distinct procedures, for two different situations. See
[ADR-0034](../adr/0034-greenfield-rebuild-over-rolling-migration.md) for why
the greenfield approach is correct for the initial build specifically.

---

## Procedure A: Greenfield full-cluster rebuild (use this now)

Applies when nothing production-critical depends on the Proxmox cluster
staying up throughout — true for the initial build, since HAProxy currently
only fronts the old, bare-metal-hosted Nextcloud instance, entirely outside
this cluster.

### 1. Repoint traffic around the cluster entirely

On the RV320, change the existing NAT/port-forward rule from HAProxy's VIP
to the bare-metal reverse proxy's IP directly. Production traffic keeps
flowing throughout the rebuild, fully bypassing Proxmox/HAProxy.

### 2. Wipe and reinstall all 3 nodes simultaneously

Using the answer-file automation in `proxmox-host/` (PVE 9.2, ZFS mirror
boot disks — see that directory's README). No need to sequence these one
at a time; there's no quorum to preserve.

**This destroys the existing k3s study cluster with no preservation path —
confirmed as an accepted, deliberate clean slate.**

### 3. Form a brand-new Proxmox cluster

From the first node:
pvecm create <cluster-name>
From the other two:
pvecm add <ip-of-first-node>

### 4. Confirm health
pvecm status
All 3 nodes should show healthy quorum before proceeding to OpenTofu.

### 5. Continue the normal bootstrap sequence

OpenTofu (VM provisioning) → Ansible (base config, RKE2, Longhorn, VLAN
network config) → ArgoCD bootstrap → GitOps takeover — see
[ADR-0025](../adr/0025-bootstrap-ordering-runbook.md).

### 6. Repoint traffic back once the new HAProxy VM is live

Once the rebuilt HAProxy VM is up and correctly configured (fronting the
still-bare-metal old Nextcloud, and eventually the new k8s-hosted one),
revert the RV320's NAT/port-forward rule back to HAProxy's VIP.

---

## Procedure B: Rolling, one-node-at-a-time reinstall (future maintenance)

Applies once the new cluster is genuinely in production use and losing
quorum during a rebuild would actually matter — e.g. a future disk layout
change on one node, long after this initial build. Not used for the initial
build itself (see Procedure A above and ADR-0034 for why).

**Precondition:** HAProxy on at least one *other* node must remain up
throughout — VRRP will fail over the VIP away from the node being worked on.

1. **Remove the node from the Proxmox cluster**, run from a surviving node:
pvecm delnode <hostname>
   Skipping this step and reinstalling directly can cause certificate/
   fingerprint conflicts when rejoining.

2. **Reinstall Proxmox** on the affected host, using the answer-file
   automation in `proxmox-host/`.

3. **Rejoin the cluster**, run from the freshly installed node:
pvecm add <ip-of-existing-cluster-member>

4. **Confirm health** before touching the next node:
pvecm status
   Must show all remaining nodes with quorum before proceeding.

5. **Recreate that host's HAProxy VM** and any other VMs that were local to
   that host (anything on local storage is gone after reinstall, not just
   paused).

6. **Confirm HAProxy VRRP** has the new instance participating correctly
   before starting the next node.

### Notes

- With a 3-node Proxmox cluster, quorum requires 2 of 3 votes. During this
  procedure you are running at the bare minimum (2 of 3) — do not start a
  second node's reinstall until the first has fully rejoined and shows
  healthy.