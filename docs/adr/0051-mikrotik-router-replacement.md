# ADR-0051: Router replacement — MikroTik RB5009UG+S+IN replaces the Cisco RV320

**Status:** Accepted — target state confirmed, implementation pending

## Context
The Cisco RV320 (`tycho`) has been on the EOL replacement backlog
since early in this project. A MikroTik RB5009UG+S+IN has been
acquired to replace it. Given how central this device is — WAN
gateway, all 6 VLAN interfaces, firewall, NAT, and VPN — this warrants
the same careful "document target state, review, then implement"
process used for the ZTNA build, given the blast radius of a mistake
here is genuinely the whole network, not a single service.

## Decision

### Naming: a name swap, not a simple addition
- The new MikroTik → `medina` (taking the name currently held by one
  of the two HPE 5130 switches)
- The switch currently named `medina` → renamed to `tycho` (taking
  the name of the retiring RV320)
- The RV320 (`tycho`) → fully retired
- `anderson` (the second switch) → unchanged

This preserves the existing "network/security infrastructure = Belter
stations" naming convention (ADR-0035) while cleanly retiring the old
router's name rather than leaving it orphaned.

### IaC tooling: OpenTofu via the `terraform-routeros/routeros` provider
Verified as a real, actively-maintained provider (330 GitHub stars,
regular releases, MPL-2.0, listed directly in the OpenTofu registry,
compatibility-tested against RouterOS 7.x) — not a guess, confirmed
before committing to this approach. Requires RouterOS ≥7.1beta4 and
the router's REST API enabled (a one-time manual step: generate root +
HTTPS certificates via `/certificate`, enable the `www-ssl` service) —
consistent with this project's "account/initial-access setup is the
one manual exception" pattern used throughout.

### Full topology preserved exactly — IPs, VLANs, DHCP, NAT, and firewall rules all unchanged from the RV320
Every VLAN gateway IP, every DHCP static reservation (including the
pre-existing `kvm001`/`plexi`/`reversi`/`cloudi`/`nfs`/Devolo/MFP
leases), every NAT port-forward, and every one of the RV320's 14
explicit-allow firewall rules were transcribed faithfully from the
live device before any RouterOS translation began. See
`docs/mikrotik-rb5009-target-state.md` for the complete, reviewed
specification.

One structural difference worth noting: the RV320's default-deny
behavior was implicit; RouterOS requires an **explicit** final `drop`
rule in the `forward` chain to achieve the same effect — a genuine
translation detail, not a behavior change.

### VPN: migrating OpenVPN to WireGuard
The RV320's OpenVPN server (TCP 1194, password+certificate,
172.31.0.0/24 client pool) is being replaced with WireGuard —
RouterOS-native, simpler, and avoids OpenVPN's heavier setup. One peer
per device (Mac, iPhone), each with its own locally-generated keypair;
the router holds only public keys. Confirmed working on both target
platforms via WireGuard's own official first-party apps.

Client subnet retained as 172.31.0.0/24 for continuity — no technical
reason to change it. Confirmed explicitly: VPN clients currently sit
in the same "LAN" context as any physically-connected device, subject
to the identical 14 firewall rules — WireGuard peers will be treated
identically, preserving current behavior exactly rather than
introducing an implicit scope change during the migration.

### IPv6: disabled
Every firewall rule and security control built throughout this entire
project has been designed and reasoned about in IPv4 terms only. The
RV320's 14 firewall rules contain zero IPv6 addresses — if IPv6 was
active without matching IPv6 firewall coverage, that would have been a
real, pre-existing gap. Rather than audit and maintain two parallel
security models indefinitely for a home-lab scale that doesn't need
IPv6's actual benefit (global address-space conservation), IPv6 is
being disabled entirely on the new router.

## Consequences
- Cutover sequencing: rename the switch first (lower risk, already-
  proven hardware), confirm DNS/inventory updated and working, only
  then bring up the MikroTik as `medina` once the name is genuinely
  free.
- Every place referencing `tycho`/`medina` by name needs updating once
  the rename happens: `station.solsys.dev` DNS records on
  Titania/Oberon, Ansible inventory, SSH known-hosts entries, and
  various ADR/documentation cross-references throughout this project.
- **Deferred, not decided**: whether DNS should move from
  Titania/Oberon to RouterOS's own DNS server. Worth revisiting once
  RouterOS's DNS capabilities are better understood and the router
  itself is confirmed stable in its primary role — not decided
  alongside the router replacement itself, to avoid conflating two
  separate architectural changes.
- Not yet done: translating this confirmed target state into literal
  RouterOS firewall/VLAN/NAT syntax, and planning the actual physical
  cutover with a genuine rollback path.

## Addendum: bootstrap in progress

Router successfully bootstrapped to a minimal working state (bridge +
VLAN 1 only, single port, confirmed working end-to-end). Full bootstrap
procedure, exact commands, and real gotchas encountered are documented
in `opentofu/medina/README.md`, kept alongside the actual
implementation rather than duplicated here. Remaining work (additional
ports, deferred VLANs, firewall, NAT, WireGuard, OpenTofu import of the
manually-created state) tracked there too.