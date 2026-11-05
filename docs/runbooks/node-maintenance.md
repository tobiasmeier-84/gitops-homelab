# Runbook: RKE2 node maintenance (VM-level change, one node at a time)

First used on 2026-11-02 to change the CPU type of the three RKE2 node VMs
([ADR-0052](../adr/0052-rke2-node-cpu-type.md)). It applies to anything that
needs a node VM stopped: CPU/RAM/NIC changes with `qm set`, work on a Proxmox
host, a full power cycle of a guest.

| Node | VM id | Proxmox host |
|---|---|---|
| enceladus | 201 | ceres |
| mimas | 202 | eros |
| rhea | 203 | pallas |

Live VMs are changed with `qm`, not OpenTofu: the `proxmox-vm` module has
`lifecycle { ignore_changes = all }` (guard of 2026-10-23), so `tofu apply` never
touches a running VM. Keep the code in `opentofu/` in sync by hand.

## Rules
- **One node at a time.** All three nodes are RKE2 servers with etcd; two must
  stay up for quorum.
- Run `kubectl` through a node that is **not** the one being worked on:
  `ssh admin@<other node>.orbit.solsys.dev 'kubectl ...'`.
- Not during backup activity: prepare Mon/Wed/Fri 06:00, upload nightly from 01:05
  to 08:00 (it ends within seconds when everything is already uploaded). Check
  `kubectl -n rocinante get jobs`.
- Keep the VM down as short as possible. By default (`replica-replenishment-wait-interval`
  600 s) Longhorn reuses the old replicas if the node is back within 10 minutes
  instead of rebuilding them.
- A CPU type change needs a full stop/start. A reboot inside the guest does not
  apply it.

## 1. Pre-flight (read-only)
```bash
kubectl get nodes -o wide
kubectl get pods -A --no-headers | grep -v -E 'Running|Completed'      # expect nothing
kubectl -n longhorn-system get volumes.longhorn.io --no-headers \
  -o custom-columns=S:.status.state,R:.status.robustness | sort | uniq -c
kubectl -n longhorn-system get replicas.longhorn.io --no-headers \
  -o custom-columns=VOL:.spec.volumeName,NODE:.spec.nodeID,STATE:.status.currentState | sort
kubectl get pods -A -o wide --field-selector spec.nodeName=<node>       # what will move
kubectl get pdb -A
kubectl -n rocinante get jobs
kubectl cnpg status barbapiccola -n rocinante                           # who is primary
```
Every volume should be `attached healthy` with replicas on all three nodes. The
detached volume (`rocinante-stage`) is expected, see the rhea special case.

## 2. Special cases
**The Postgres primary runs on the node.** The disruption budget
`barbapiccola-primary` allows no disruption, so the drain would hang. Switch over
first with the plugin (installed by the Ansible role `rke2-kubectl-env`, tag
`cnpg_plugin`; the version in `ansible/group_vars/rke2_nodes.yml` must match the
operator):
```bash
kubectl cnpg promote barbapiccola <replica instance> -n rocinante
sleep 20; kubectl -n rocinante wait --for=condition=Ready --timeout=120s cluster/barbapiccola
kubectl cnpg status barbapiccola -n rocinante
curl -s -o /dev/null -w "%{http_code}\n" https://nextcloud.app.solsys.dev/status.php   # 200
```
The apps lose their database connection for a few seconds. A replica needs nothing.

**rhea.** The volume `rocinante-stage` (backup staging) has a single replica, on
rhea. With Longhorn's default drain policy the instance-manager budget of rhea then
never releases and the drain hangs. While the volume is detached (no upload in
progress), allow it temporarily and put it back afterwards:
```bash
kubectl -n longhorn-system patch settings.longhorn.io node-drain-policy --type=merge -p '{\"value\":\"allow-if-replica-is-stopped\"}'
# ... maintenance ...
kubectl -n longhorn-system patch settings.longhorn.io node-drain-policy --type=merge -p '{\"value\":\"block-if-contains-last-replica\"}'
```
Plex (`behemoth`) is offline while rhea is down; its media volume is pinned to rhea.

## 3. Per node
```bash
# drain (via another node); ends with "node/<node> drained"
kubectl cordon <node> && kubectl drain <node> --ignore-daemonsets --delete-emptydir-data --timeout=10m

# on the Proxmox host, immediately afterwards (replace the qm set line with the change you need)
qm shutdown <vmid> --timeout 240 && qm set <vmid> --cpu x86-64-v2-AES && qm start <vmid>
qm config <vmid> | grep -E "^(cpu|scsi[0-9])"        # passthrough disks still attached?

# wait for the node, uncordon
until kubectl get node <node> --no-headers 2>/dev/null | grep -q " Ready"; do sleep 10; done
kubectl uncordon <node>

# gate before the next node: no attached volume degraded/unknown (3-10 minutes)
until [ "$(kubectl -n longhorn-system get volumes.longhorn.io --no-headers \
  -o custom-columns=S:.status.state,R:.status.robustness | grep -c -E "^attached +(degraded|unknown)")" = "0" ]; do sleep 30; done
```
Verify in the guest, e.g. for the CPU type
`for f in ssse3 sse4_2 popcnt aes; do grep -q -w $f /proc/cpuinfo && echo "$f=yes" || echo "$f=NO"; done`,
and on rhea `findmnt /mnt/behemoth`. Finally: no unhealthy pods, `kubectl cnpg status`
healthy, Nextcloud `status.php` returns 200.

## Gotchas seen
- The drain first prints "Cannot evict pod ... violate the pod's disruption budget"
  for Longhorn's instance-manager. That is normal; Longhorn releases the budget a
  few seconds later. If it is still stuck after about 3 minutes, stop and look.
  Never use `--force` or `--disable-eviction`.
- Right after a restart, `FailedAttachVolume ... engine image ... not deployed on at
  least one of the replicas' nodes` for a few seconds is transient.
- Since 2026-11-05 all VMs run the guest agent (ADR-0053): `qm shutdown` asks the guest
  through it, and `qm agent <vmid> ping` shows that the channel is alive after a start.
  (Until then `qm shutdown` fell back to ACPI; it worked on all three nodes.)
- `qm` on pallas prints `storage 'canterbury' does not exist`: a stale reference,
  harmless (see BACKLOG).
- `tofu plan` for `environments/prod` currently fails while refreshing rhea (see
  BACKLOG); `tofu plan -refresh=false` compares code against state only.
