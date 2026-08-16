# ADR-0045: ZTNA architecture for admin-plane access (tool choice deferred)

**Status:** Proposed — tool selection open, architecture and
requirements accepted

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

## Tool choice — deferred, two real candidates

**Pomerium** — mature, OIDC-native (plugs directly into the existing
Entra ID setup with no new identity plumbing), excellent HTTP-native
experience. Does support TCP/SSH, but it's a second-class capability:
requires client-side tooling (`pomerium-cli`/Pomerium Desktop) rather
than the clientless experience its HTTP routes offer, or a more
involved "Native SSH" mode requiring SSH servers to trust Pomerium's
own CA. Needs genuine L4/TCP-mode passthrough if fronted by HAProxy
(likely compatible with the existing `mode tcp` backend pattern already
used for Traefik, but unverified in practice).

**Pangolin** — WireGuard-based, treats HTTP and TCP/SSH as equally
first-class under one control plane and identity model — a
structurally better fit for a mixed HTTP+SSH requirement. Open source.
Current production maturity not yet confirmed; needs dedicated research
before committing, not a decision to rush under momentum from an
unrelated work session.

## Consequences
- `phobos`/`deimos` are reserved exclusively for this project — not
  available for other Mars-tier or general infrastructure use.
- Decision on Pomerium vs. Pangolin deferred to a dedicated research
  session (a plausible candidate for the Research feature, given the
  genuine architectural trade-offs involved).
- Once built, `docs/BACKLOG.md`'s existing "ZTNA for admin-plane
  interfaces" item is superseded by this ADR and should be marked as
  such.