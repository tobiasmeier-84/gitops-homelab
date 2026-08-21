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
- **Backlog item**: remove Deimos's static `/etc/hosts` entries once
  proper internal DNS (Titania/Oberon, CoreDNS + Pi-hole, per the
  earlier DNS/filtering design discussion) is actually built and proven
  reliable — the `/etc/hosts` entries are a deliberate interim fix, not
  a permanent architecture decision.
- The router's `c-ares`-incompatible DNS behavior is worth keeping in
  mind for any *other* future service with a strict DNS resolver, not
  just this one.