# ADR-0047: Pomerium ZTNA deployment — real-world gotchas and fixes

**Status:** Accepted

## Context
ADR-0045 decided the ZTNA architecture (Pomerium, single VM given the
`iapetus` no-HA precedent) and ADR-0046 established the naming
(`belt.mcrn.solsys.dev` for Proxmox, `deimos.mcrn.solsys.dev` for
Pomerium's own authenticate service, `deimos.orbit.solsys.dev` for the
VM's own identity). This ADR documents what was actually needed to get
it working end to end, since several non-obvious issues surfaced during
implementation that are worth recording precisely.

## Decision — final deployment shape

- **Single VM**: `deimos`, dual-NIC (MGMT `10.10.10.34` + DMZ-INGRESS
  `10.10.40.14`), native `.deb` package install (Cloudsmith apt repo),
  systemd-managed — no Docker, consistent with HAProxy/keepalived's own
  native-package precedent.
- **Certificate**: certbot + Cloudflare DNS-01, same pattern as
  `iapetus`/MinIO (Deimos sits outside the k8s cluster, so cert-manager
  isn't the natural fit).
- **Routing**: HAProxy's existing VRRP trio gained a new SNI-routed
  backend (`deimos_mcrn`) for `belt.mcrn.solsys.dev` and
  `deimos.mcrn.solsys.dev`, reusing the existing floating IP and HA
  mechanism rather than building separate redundancy for Pomerium.
- **Multi-backend routing**: Pomerium routes to all 3 Proxmox nodes by
  their real per-node hostnames (not raw IPs), since Proxmox's web UI
  is cluster-aware — any node can manage the whole cluster, making this
  genuine load-balancing/failover, not just a single soft entry point.
- **Two separate Entra ID App Registrations required**: App Roles are
  scoped per-application, not shared globally. The existing
  `belt-captain`/`belt-crew`/`belt-passenger` groups needed a **second**
  set of App Role assignments created specifically on Pomerium's own
  App Registration (`pomerium-mcrn`) — the same groups, reused, but a
  distinct role-assignment object per consuming application. Without
  this, a token issued for Pomerium would carry an empty `roles` claim
  even for a user correctly in the group.
- **Proxmox's own separate OIDC app also needed updating**: its
  `redirect_uris` only listed the direct per-node hostnames
  (`ceres.belt.solsys.dev:8006` etc.) — once Proxmox became reachable
  via `belt.mcrn.solsys.dev`, its own SSO broke until that hostname was
  added as an additional valid redirect URI. Both direct-node access and
  ZTNA-gated access remain valid login paths simultaneously.

## Real issues found and fixed during implementation

1. **`idp_client_id` used a bare Jinja reference instead of
   `lookup('env', ...)`** — same class of bug as the earlier ArgoCD
   `argocd-cm` incident (ADR-0040's addendum). Ansible variables and
   shell environment variables are separate namespaces; a bare
   `{{ var }}` never resolves to an exported shell variable.
2. **certbot's DNS-01 propagation wait (10s default) was too short for
   Cloudflare** — increased to 60s via
   `--dns-cloudflare-propagation-seconds 60`.
3. **`/etc/systemd/system/pomerium.service.d/` didn't exist** — `copy`
   doesn't create parent directories; needed an explicit `file: state:
   directory` task first.
4. **Certbot's own directory permissions blocked the `pomerium` user
   entirely** — `/etc/letsencrypt/archive/` and `/etc/letsencrypt/live/`
   are `0700` root-only by default, at *every* level (the per-domain
   subdirectory, not just the top level). A certbot deploy hook now
   fixes `chgrp`/`chmod` on both the parent directories and the
   per-domain directories and the private key file itself, re-running
   automatically on every renewal.
5. **Session cookie didn't survive the redirect between
   `belt.mcrn.solsys.dev` and `deimos.mcrn.solsys.dev`** — two distinct
   hostnames, cookies don't share across them by default. Fixed with
   `cookie_domain: mcrn.solsys.dev`, scoping the session cookie to the
   shared parent domain.
6. **The most significant finding**: Envoy's DNS resolver (`c-ares`)
   rejected the home router's DNS relay responses with `"Misformatted
   DNS reply"` — a stricter parser than `dig`/glibc's resolver, which
   silently tolerate the same malformed responses. This exact router
   behavior was actually observed once before, early in this project
   (a `dig` warning dismissed at the time as harmless), and turned out
   to matter once something with a strict parser depended on it.
   **Fixed with static `/etc/hosts` entries on Deimos** for the 3
   Proxmox hostnames — arguably a good practice independent of the
   router bug, since it removes a DNS dependency from the critical
   admin-access path entirely.

## Consequences
- Genuine end-to-end success confirmed: real Entra ID login, correct
  `belt.captain` role claim recognized, correct routing to a healthy
  Proxmox node, and Proxmox's own separate SSO also working through the
  new hostname.
- ~~Backlog item: remove Deimos's static `/etc/hosts` entries once
  proper internal DNS is built and proven reliable~~ **RESOLVED** —
  CoreDNS (Titania/Oberon) confirmed reliable, static entries removed,
  Ansible task removed to prevent re-creation on future runs.
  a permanent architecture decision.
- The router's `c-ares`-incompatible DNS behavior is worth keeping in
  mind for any *other* future service with a strict DNS resolver, not
  just this one.

## Addendum: non-browser (API token) access stays outside ZTNA — investigated, deliberately deferred

Removing the MGMT-zone firewall rules entirely (this ADR's original
goal) surfaced a real gap: OpenTofu's own workflow authenticates to
Proxmox via a direct API token on port 8006, from the operator's own
workstation — a non-browser flow Pomerium's OIDC-based session model
was never designed to gate. Investigated Pomerium's own answer to this
(**Service Accounts** — bearer-token machine-to-machine auth, evaluated
by the same policy engine as human sessions) and found it is a
**Pomerium Enterprise / Pomerium Zero feature, not available in
Pomerium Core** (the free, self-hosted tier actually deployed here).

Pricing checked directly: Zero starts at **$7/user/month** (annual
billing; $9/month monthly), Enterprise is **contact-sales, no public
price**, clearly scoped for organizations well beyond home-lab scale.
Paying for Zero specifically to unlock Service Accounts would also mean
depending on a third-party-hosted control plane for authentication —
in tension with the self-hosted, "everything stays on your own
infrastructure" reasoning that made Pomerium Core the right choice in
ADR-0045 in the first place.

**Decision: stay on Pomerium Core, don't pay for Service Accounts.**
Instead, keep a narrow firewall exception — direct port 8006 access
from the operator's own known workstation/subnet only — for the
OpenTofu/API-token workflow specifically, while all human/browser-based
admin access continues to route through Pomerium as designed. This is
still a substantial narrowing from the original "any device on this
VLAN can reach MGMT" rule down to "one specific known source," even
though it isn't the full zero-exception state originally envisioned.
Revisit only if a second person ever needs genuine service-account-style
access (not just the current operator's own convenience).

## Addendum: SSH access implemented — Native SSH for Proxmox, Jump-Host mode for switches

Following the backlog item above (HPE Comware CA-certificate support
unconfirmed), SSH access was built out for both target categories,
using the two different mechanisms Pomerium provides — deliberately
avoiding testing Native SSH against production switches given the risk
profile discussed above.

**Proxmox hosts (`ceres`/`eros`/`pallas`): Native SSH, Captain-only, `root` only.**
Standard OpenSSH confirmed compatible with `TrustedUserCAKeys`. Routes
restrict both the role claim *and* the requested username explicitly:
```yaml
policy:
  - allow:
      and:
        - claim/roles: "belt.captain"
        - ssh_username:
            is: "root"
```
`belt.crew` was deliberately given no SSH route at all — during
rollout, a real gap was found where a crew-tier identity could request
`root@ceres@...` and receive full root, since Native SSH's policy only
gates *whether a connection is permitted*, not *which username is
requested* — that requires the explicit `ssh_username` check above.
Crew's access model stays scoped to the Proxmox web UI (`PVEVMAdmin`)
only; SSH was not extended to crew rather than building a limited
Linux account to accommodate it.

**Network switches (`medina`/`anderson`): Jump-Host mode, Captain-only.**
Confirms the backlog item's caution was warranted — research strongly
suggested Comware's SSH server only supports classic per-key
`public-key peer import sshkey` authentication, not OpenSSH CA
certificates. Jump-Host mode was used instead, requiring **zero
switch-side configuration changes** — Pomerium only gates whether the
connection attempt is permitted; the switch's own existing key-based
auth (already in place from this project's earliest setup) handles the
actual login. Enabled via:
```yaml
runtime_flags:
  ssh_allow_direct_tcpip: true
```

## Two real configuration gotchas found during SSH rollout

1. **Runtime flags require a nested key, not a bare top-level one.**
   `ssh_allow_direct_tcpip: true` at the document root is silently
   ignored (no error — Pomerium just doesn't apply it). Must be nested:
```yaml
   runtime_flags:
     ssh_allow_direct_tcpip: true
```
   Inferred from a Kubernetes ingress-controller reference showing
   `RuntimeFlags` as its own distinct field, before being confirmed
   correct by testing — no direct authoritative Core example was found
   for this specific structure.

2. **Jump-Host mode's `-J` connection matches routes by the real
   destination hostname, not the route's declared name.** Named routes
   (`from: ssh://medina`) only match the `user@route@pomerium` syntax
   used by Native SSH connections. A Jump-Host (`-J`) connection sends
   the actual target hostname during handoff — confirmed directly via
   Pomerium's own debug logs (`"newHostname":"medina.station.solsys.dev"`,
   `"deny-why-true":["route-not-found"]`). Fixed by setting `from:` to
   the real hostname:
```yaml
   - from: ssh://medina.station.solsys.dev
     to: ssh://medina.station.solsys.dev:22
```
   This distinction isn't obvious from the documentation alone —
   diagnosed by reading Pomerium's own debug-level logs directly rather
   than guessing from the docs a second time.

## Addendum: SSH access extended to all remaining VMs — Deimos/Titania/Oberon excluded as break-glass

Following the Proxmox and switch rollout, Native SSH was extended to
every remaining admin-plane VM (RKE2 nodes, HAProxy trio, `iapetus`),
using the same CA-trust mechanism and role (`proxmox-ssh-ca`, generic
enough to apply unchanged beyond its original Proxmox target). All
routes: Captain-only, `admin` user (these VMs use cloud-init's default
`admin` account, not `root` like the Proxmox hosts).

**Deliberately excluded: `deimos`, `titania`, `oberon`.** These three
host the ZTNA infrastructure itself (Pomerium; CoreDNS) or its direct
dependencies. Gating their own SSH access behind Pomerium would create
a genuine lockout risk — if Pomerium itself ever failed, fixing it
would require SSH access that itself depends on Pomerium working. These
three keep direct SSH access as a deliberate, permanent break-glass
path, not an oversight or a temporary gap.

This completes the SSH-over-ZTNA rollout — every admin-plane VM except
the ZTNA infrastructure's own foundation is now reachable only through
identity-verified, policy-gated Pomerium sessions.