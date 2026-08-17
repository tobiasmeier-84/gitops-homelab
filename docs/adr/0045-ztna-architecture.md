# ADR-0045: ZTNA architecture for admin-plane access (tool choice deferred)

**Status:** Accepted

## Context
Admin-plane services (Proxmox web UI today; potentially SSH to network
devices and Proxmox hosts) are reachable only via direct network-level
firewall rules granting specific source networks access to the MGMT
VLAN. This has two real problems: it doesn't scale to giving a
demo/recruiter identity (`belt-passenger`) remote access without a
VPN, and it trusts network *location* rather than verified *identity* —
anyone on a permitted source network gets access, regardless of who
they actually are.

## Decision

### Goal: collapse MGMT-zone reachability to a single, identity-gated choke point
All admin-plane access — from anywhere, including the internal home
network, not just external/remote — should require passing through a
Zero Trust Network Access (ZTNA) gateway that authenticates against the
existing Entra ID setup (reusing the `belt-*` groups already built).
Once live, the existing direct-access firewall rules to the MGMT VLAN
should be removed entirely; the ZTNA gateway becomes the only path in.

### Scope: both HTTP(S) admin UIs and non-HTTP protocols
- **HTTP(S)**: Proxmox web UI (port 8006) — the straightforward case,
  well-served by any HTTP-native identity-aware proxy.
- **Non-HTTP**: SSH to network devices (`medina`/`anderson`) and
  potentially the Proxmox hosts themselves — genuinely harder, and the
  deciding factor in the tool choice below.

### Placement: dedicated VMs, Mars-tier naming, dual-NIC
`phobos` and `deimos` (Mars moons — reserved specifically for this
project per ADR-0035's amendment, given the genuine security-boundary
significance of a ZTNA gateway; distinct from the Uranus tier used for
general special-infrastructure VMs, see ADR-0044). Two dedicated VMs
(not containers, not sharing a host with anything else) for real
isolation of a security-boundary component. Each needs two NICs:
**DMZ-INGRESS** (to receive gated traffic) and **MGMT** (to actually
reach the protected admin surfaces) — structurally the same shape as
the HAProxy trio's own multi-VLAN placement.

### Traffic path: reuse the existing HAProxy VRRP trio, don't duplicate HA
Rather than building separate HA/VRRP for the ZTNA gateway, Phobos/
Deimos become a **second backend pool** behind the already-existing
HAProxy trio — same floating IP, same health-check mechanism, routed
by SNI alongside the existing Traefik/RKE2 backend. This also gives
internal-network users a single, consistent path: reachable both
directly (if `tycho`'s inter-VLAN routing permits reaching DMZ-INGRESS,
a much narrower and safer rule than "reach MGMT directly") and via the
existing external path, with no hairpin-NAT concerns since DMZ-INGRESS
is already the common meeting point for both.

### Non-goal: published applications (Nextcloud, Harbor, etc.) do not need ZTNA
These already have their own identity gate (app-level SSO). Layering
ZTNA in front of something already identity-gated and meant to be
public would be redundant friction, not additional real security. ZTNA
is specifically for admin surfaces with no app-level SSO of their own.

## Tool choice: Pomerium

Following dedicated research (see `docs/research/ztna-pomerium-vs-pangolin.md`),
**Pomerium** (Core, Apache-2.0) is the chosen tool, over Pangolin and
Teleport.

### Why Pomerium won

- **Licensing is the deciding factor.** Pomerium Core is Apache-2.0 and
  includes everything needed — Entra ID OIDC, HTTP routing, TCP
  tunneling, and Native SSH — with no paywall. Pangolin's Community
  Edition does **not** include external IdP support or SSH at all;
  both are gated behind its Enterprise Edition, which — while free for
  personal/home use — requires an activated commercial license key.
  Adopting Pangolin would mean depending on a vendor's licensing
  decisions for the two capabilities this project actually needs.
- **The exact deployment topology is explicitly documented and
  supported.** Pomerium's own docs specifically warn against sitting
  behind an HTTP-mode proxy and instruct configuring the front-end load
  balancer in L4/TCP mode — precisely the existing HAProxy VRRP
  SNI-passthrough setup already built (ADR-0031, ADR-0040). There's a
  dedicated guide for "SSH over port 443 through an L4 edge." Pangolin,
  by contrast, is designed to *be* the edge itself (terminates TLS via
  Traefik, needs public 80/443 + WireGuard UDP ports) — a structurally
  awkward fit behind an existing HAProxy layer.
- **SSH without client tooling, for standard OpenSSH targets.**
  Pomerium's Native SSH mode acts as an SSH certificate authority,
  issuing short-lived certificates via a standard `ssh` client — no
  agent, no per-user key management. Works directly against Proxmox
  hosts (standard OpenSSH, supports `TrustedUserCAKeys`).
- **Longer track record and an independent security audit.** In
  production since 2019, backed by a $18M total raise (Series A led by
  Benchmark, June 2024), and audited by Cure53 (March 2021, findings
  resolved). Pangolin is younger (first commits Sept 2024) and has
  disclosed two Critical/High CVEs in its authentication and 2FA
  components as recently as Dec 2025.

### Known caveat: HPE Comware switches may not support Native SSH mode

Native SSH CA-trust requires the target SSH server to support
`TrustedUserCAKeys` — standard OpenSSH does, but Comware's SSH stack
may not (untested as of this ADR). If confirmed unsupported, fall back
to Pomerium's TCP-tunnel or ProxyJump mode for `medina`/`anderson`
specifically — ProxyJump doesn't require the upstream to trust the CA,
so it works regardless. Proxmox hosts are expected to work via full
Native SSH without this fallback. **Verify directly against a real
Comware switch before finalizing the switch-access design.**

### Staged rollout plan
1. Deploy Pomerium Core on `phobos`/`deimos` (2 vCPU/2-4GB each),
   wire Entra ID OIDC (`idp_provider: azure`), add a groups claim
   consistent with the existing `belt-*` group scheme.
2. Gate the Proxmox VE UI first (HTTP route, `belt-captain`/`belt-crew`
   policy). Point HAProxy's existing SNI-based backend selection at
   Pomerium for this hostname. Confirm a policy change actually revokes
   access.
3. Add SSH for Proxmox hosts via Native SSH (install Pomerium's CA
   public key as `TrustedUserCAKeys`).
4. Test Native SSH against a Comware switch; fall back to
   TCP-tunnel/ProxyJump if unsupported.
5. Only once confirmed working end-to-end: remove the existing
   direct-access firewall rules to the MGMT VLAN, per this ADR's
   original goal.

## Consequences
- `phobos`/`deimos` are reserved exclusively for this project — not
  available for other Mars-tier or general infrastructure use.
- Full research comparison saved as `docs/research/ztna-pomerium-vs-pangolin.md`
  for future reference (e.g., if Pangolin's licensing changes, or if
  the Comware SSH caveat forces a reconsideration).
- Once built, `docs/BACKLOG.md`'s existing "ZTNA for admin-plane
  interfaces" item is superseded by this ADR and should be marked as
  such.