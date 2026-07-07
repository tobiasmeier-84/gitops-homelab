# ADR-0032: Perimeter firewall (Cisco RV320) — EOL risk accepted

**Status:** Accepted risk (backlogged upgrade)

## Context
The Cisco RV320, sitting at the network's internet-facing perimeter (fronting the DMZ-INGRESS VLAN), was declared End-of-Life by Cisco in 2019 and has continued to receive security advisories (DoS, RCE, privilege escalation) as recently as 2024–2025, with no guarantee of ongoing patches. Its firewall capability is also limited to basic access-rule ACLs rather than a granular, stateful, zone-based policy engine.

## Decision
Continue using the RV320 for now. Treat replacement (with OPNsense, pfSense, or a Mikrotik/UniFi gateway) as an explicit backlog item, not a blocker to proceeding with the rest of the build.

## Reasoning
Consistent with other hardware-cost trade-offs already accepted in this design (ADR-0008, ADR-0009): the capability gap is real, but replacing perimeter hardware is a nontrivial cost/effort that isn't proportionate to block the rest of the platform build on. The device does support the VLAN count and basic ACL structure this design needs (ADR-0031) today.

## Consequences
The internet-facing perimeter runs on hardware with known, disclosed vulnerabilities and coarse-grained firewall rules. Revisit if: a CVE against the RV320 is disclosed with known active exploitation, the DMZ-INGRESS traffic profile changes materially, or budget/opportunity allows a straightforward replacement.