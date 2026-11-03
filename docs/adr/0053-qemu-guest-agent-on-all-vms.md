# ADR-0053: QEMU guest agent on every VM

**Status:** Accepted - rollout started 2026-11-03

## Context
None of the VMs ran the QEMU guest agent. Without it Proxmox cannot ask a guest
anything: `qm guest exec` and `qm agent <id> ping` fail ("QEMU guest agent is not
running"), `qm shutdown` falls back to ACPI, guest IP addresses are not shown, and
snapshots or backups cannot freeze the filesystem. It also kept us from checking a
host key of a rebuilt guest from the Proxmox side during the ADR-0052 rollout.

## Decision
- Every VM runs `qemu-guest-agent` and has the Proxmox option `agent: 1`.
- OpenTofu: the `proxmox-vm` module sets `agent { enabled = true }` for all VMs it
  builds, and `bootstrap-minio` does the same for `iapetus`. Their cloud-init installs
  the package, because the provider waits for the agent to answer when it creates a VM.
- Ansible: the `common` role (all VMs) installs and starts the package, tag
  `guest_agent`, so existing VMs and future rebuilds are covered the same way.
- The cloud-init snippet resources ignore later content changes
  (`ignore_changes = [source_raw]`). Proxmox derives the cloud-init instance id from
  the user-data, so rewriting the snippet of a live VM could make cloud-init repeat its
  first-boot steps (new SSH host keys, runcmd) at the next start. The snippet only
  matters when a VM is created.
- Existing VMs are changed live, not through OpenTofu (the 2026-10-23 guard stays).

## Rollout procedure
1. `ansible-playbook site.yml --tags guest_agent --limit 'all:!belt'` installs the
   package everywhere. No restart.
2. A full stop/start per VM applies `qm set <vmid> --agent enabled=1`, because the
   virtio-serial channel cannot be hot-plugged. Done one VM at a time with a health
   check before and after, and verified with `qm agent <vmid> ping`.
3. The three RKE2 nodes get the option as a pending change; it takes effect at their
   next planned stop/start, following docs/runbooks/node-maintenance.md.

## Consequences
- Another restart per VM; for the RKE2 nodes it is deferred to the next maintenance.
- `iapetus` has no `ignore_changes = all` guard, so `tofu plan` in `bootstrap-minio`
  shows a pending change until its live option is set. Do not apply that plan.
- Rollback per VM: `qm set <vmid> --agent 0` plus a full stop/start.
