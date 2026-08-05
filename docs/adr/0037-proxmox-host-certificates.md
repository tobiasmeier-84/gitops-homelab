# ADR-0037: Proxmox host certificates — individual per-node, not wildcard

**Status:** Accepted

## Context
Proxmox nodes shipped with self-signed certificates by default. ADR-0035 specified wildcard certificates for the internal `belt`/`station`/`orbit` tiers, including the physical hosts. Proxmox's built-in ACME client is designed around one certificate per node (each node runs its own DNS-01 challenge independently); a genuinely shared wildcard certificate across all 3 nodes would require ordering it once and manually distributing/syncing the same cert+key to the other nodes, since Proxmox's automatic renewal only runs on whichever node originally placed the order.

## Decision
Individual Let's Encrypt certificates per node (`ceres.belt.solsys.dev`, `eros.belt.solsys.dev`, `pallas.belt.solsys.dev`), issued via Proxmox's built-in ACME client with a Cloudflare DNS-01 plugin — not a shared wildcard certificate.

## Reasoning
The wildcard approach's benefit here is mostly aesthetic (one cert object instead of three) — it doesn't meaningfully reduce operational surface, since sharing a wildcard cert across nodes not managed by the same ACME order actually *adds* complexity (manual distribution, custom renewal-sync logic) rather than removing it. Individual per-node certs are the standard, well-documented Proxmox pattern, each with fully automatic independent renewal.

## Consequences
This is a deliberate, small deviation from ADR-0035's letter (which specified wildcards for this tier without anticipating this Proxmox-specific constraint) — noted here explicitly rather than silently diverging. See `proxmox-host/README.md` for the setup procedure and troubleshooting.