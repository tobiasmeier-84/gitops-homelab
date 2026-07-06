# Runbook: Proxmox node reinstall / rolling migration

Used when a Proxmox host needs a clean OS reinstall (e.g. disk layout change) while keeping the cluster and its services available throughout, using the existing HAProxy + VRRP setup to absorb the affected node's downtime.

**Precondition:** the HAProxy VM on at least one *other* node must remain up throughout the whole procedure — VRRP will fail over the VIP away from the node being worked on.

## Procedure (repeat once per node, strictly one node at a time)

1. **Remove the node from the Proxmox cluster**, run from a surviving node:
   ```
   pvecm delnode <hostname>
   ```
   Skipping this step and reinstalling directly can cause certificate/fingerprint conflicts when rejoining.

2. **Reinstall Proxmox** on the affected host.
   - Target layout: ZFS mirror for the boot pool (NVMe+NVMe if a second NVMe slot is available, otherwise NVMe+SATA SSD — acceptable for a boot disk, not performance-critical).
   - Once the answer-file automated install exists (see `terraform/` / host-provisioning tooling), use it instead of the manual installer for consistency.

3. **Rejoin the cluster**, run from the freshly installed node:
   ```
   pvecm add <ip-of-existing-cluster-member>
   ```

4. **Confirm health** before touching the next node:
   ```
   pvecm status
   ```
   Must show all remaining nodes with quorum before proceeding.

5. **Recreate that host's HAProxy VM** and any other VMs that were local to that host (anything on local storage is gone after reinstall, not just paused).

6. **Confirm HAProxy VRRP** has the new instance participating correctly before starting the next node.

## Notes

- With a 3-node Proxmox cluster, quorum requires 2 of 3 votes. During this procedure you are running at the bare minimum (2 of 3) — do not start a second node's reinstall until the first has fully rejoined and shows healthy.
- The first migration pass (this runbook, as originally executed) was performed manually. Once Terraform/Ansible cover VM recreation, later repeats of this procedure should require far less manual work — only the `pvecm` steps and the physical Proxmox reinstall remain manual.
