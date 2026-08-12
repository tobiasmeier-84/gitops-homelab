# ADR-0041: RKE2 CIS profile hardening

**Status:** Accepted

## Context
Beyond the ServiceLB/Traefik exposure work (ADR-0040), no pod-level security posture had been decided for the cluster. RKE2 ships a built-in `profile: cis` mechanism that automatically applies a Kubernetes CIS Benchmark-aligned configuration — Pod Security Admission enforcement, kube-apiserver/kubelet hardening flags, audit logging — rather than requiring these to be hand-assembled.

## Decision
Enable `profile: "cis"` on all 3 RKE2 nodes, with a custom Pod Security Admission config (not RKE2's own default) that adds `longhorn-system` to the namespace exemption list alongside RKE2's built-in exemptions (`kube-system`, `compliance-operator-system`, `tigera-operator`) — added proactively, before Longhorn is actually deployed, since Longhorn's manager/CSI pods require privileged access that the default `restricted` policy would otherwise block.

Host-level prerequisites (required before RKE2's first start, not retrofittable live) are provisioned via the Ansible `rke2` role:
- A dedicated `etcd` system user/group
- RKE2's own generated CIS sysctl file, copied into `/etc/sysctl.d/`

## Reasoning
Reusing RKE2's own built-in mechanism gets a maintained, benchmark-aligned baseline for free, rather than hand-rolling equivalent Kyverno policies from scratch. Pre-exempting `longhorn-system` avoids a predictable future outage — discovering this gap *after* Longhorn is already deployed and broken is a worse time to fix it than now, while it's still a documentation-only change.

## A design decision this surfaced: Proxmox VE / Debian host-level CIS hardening is explicitly out of scope here
This ADR covers only the Kubernetes-layer CIS controls RKE2 itself manages. No official CIS benchmark exists for Proxmox VE; extending the CIS Debian Benchmark to the hypervisor hosts carries real risk of breaking cluster communication (corosync/pmxcfs) or ZFS functionality without careful, tested adaptation. Tracked separately in `docs/BACKLOG.md`, deliberately not bundled into this work.

## Verification: validated via full destroy-and-rebuild
The entire fix (host prerequisites, PSA config, `profile: cis`) was proven not just by applying it to an already-running cluster, but by **destroying all 3 RKE2 node VMs entirely and re-provisioning + re-bootstrapping from scratch** through OpenTofu + Ansible alone. The rebuilt cluster came up healthy, CIS-enforcing (confirmed by a deliberately-submitted privileged test pod being correctly rejected), and fully reachable through the existing HAProxy/Traefik ingress chain — a genuine end-to-end proof that this configuration is reconstructable from git alone, not just documented.

## A subtle Ansible bug found and fixed along the way
The RKE2 install task originally used a plain `curl | sh` pipeline. In a default shell, only the *last* command's exit code determines the pipeline's reported success — if `curl` failed (plausible immediately after a fresh VM boot, before networking is fully stable) but `sh -` still ran against empty input, it would exit `0`, and Ansible would report a false success. Combined with `creates: /usr/local/bin/rke2` (which only checks for the file's existence *before* running, never *after*), this let a completely failed install pass silently, with the real failure only surfacing several tasks later as a confusing, unrelated-looking error.

Fixed with `set -o pipefail` (requires `executable: /bin/bash`, since default `/bin/sh` may not support it) plus a small retry/delay loop for early-boot network timing. Worth remembering as a general pattern — any `curl | sh`-style Ansible task should use `pipefail`, not just this one.

## Consequences
- Every future RKE2 rebuild automatically comes up CIS-hardened, with the Longhorn exemption already in place — no manual step required at any point.
- `docs/BACKLOG.md` tracks the separate, deliberately-deferred Proxmox/Debian host-level hardening work.