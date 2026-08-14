# ADR-0042: Cross-service RBAC — Captain/Crew/Passenger tiers

**Status:** Accepted

## Context
ADR-0039 stood up Proxmox's Entra ID OIDC login but used a direct per-user
role grant as an interim measure, explicitly flagged as not scaling to a
second admin or any other access tier. A broader need also existed: a
genuine read-only identity for demonstrating this project (e.g. to a
recruiter) without exposing write access or secrets, and a self-service
tenant pattern for a real second person to deploy their own applications
in an isolated sandbox.

## Decision

### Three tiers, applied uniformly across every service
- **Captain** — full administrative control
- **Crew** — scoped operational access (or, for a tenant's own app, full
  control within their own sandbox)
- **Passenger** — read-only, mandatory default present on every domain
  from day one

### Domain-prefixed group naming, reusing the existing ship/faction theme
- `belt-*` — Proxmox (Belt objects = the physical hosts)
- `agatha-king-*` — ArgoCD (already named the "UN fleet flagship" in
  ADR-0035 — the flagship-commanding-a-fleet metaphor already fit "the
  tool controlling every other workload" before this ADR existed)
- `station-*` — network devices (**reserved**, no central AAA exists yet
  for the HPE switches/RV320 — needs RADIUS/TACACS+, a separate project)
- `mcrn-*` — cross-cutting security tooling (**reserved**, no single
  tool yet spans CrowdSec/cert-manager/oauth2-proxy/admission-control
  collectively)
- `<shipname>-*` — each future tenant's own app gets its own new ship
  identity (same naming exercise as Rocinante/Arboghast/etc.), not
  nested under ArgoCD's own name — a tenant is captain of their own
  ship, not crew on someone else's

All 12 groups for the two currently-actionable domains (`belt`, 
`agatha-king`) are created now; the 6 reserved-domain groups
(`station`, `mcrn`) are also pre-created empty, so nothing needs
renaming later when those domains become real.

### App Roles, not raw group claims
Entra ID's default `groups` claim emits **object IDs (GUIDs)**, not
readable names, for cloud-native security groups (no on-prem AD sync in
this tenant). Rather than reference opaque GUIDs in Proxmox's ACL
config, each service's App Registration defines proper **App Roles**
(`belt.captain`, `belt.crew`, `belt.passenger`), with security groups
assigned to those roles — Microsoft's documented mechanism for exactly
this translation. The `roles` claim (not `groups`) then carries readable
values, and Proxmox's `groups-claim` setting points at `roles`.

## Implementation

**Entra ID side** (`opentofu/entraid/`): `azuread_group` (all 18 groups,
15 reserved + 3 ... wait, 12 real + 6 reserved), `azuread_application`
(App Role definitions added to the existing imported `proxmox-homelab`
app), `azuread_service_principal` (imported — role assignments target
the Service Principal, not the Application Registration itself, a real
distinction in Entra ID's object model), `azuread_app_role_assignment`
(group-to-role bindings).

**Proxmox side** (new directory `opentofu/proxmox-entraid/`, not folded
into `proxmox-acme/` — this is identity/RBAC, not certificates):
`proxmox_realm_openid` (imported the existing live realm; added
`groups_claim = "roles"`, `groups_autocreate = true`, migrated the
client secret to the write-only `client_key_wo` field), 
`proxmox_virtual_environment_group` (the 3 local groups Proxmox
matches against, suffixed `-entraid` per Proxmox's own collision-avoidance
convention), `proxmox_acl` (role bindings: `belt.captain-entraid` →
`Administrator`, `belt.crew-entraid` → `PVEVMAdmin`,
`belt.passenger-entraid` → `PVEAuditor`).

## Real near-misses caught during implementation, worth remembering

- **A literal `<your-tenant-id>` placeholder string nearly got applied
  as the real `issuer_url`** — caught only by reading the `tofu plan`
  diff carefully before applying, not by any error or warning. Applying
  it would have broken OIDC login entirely, including admin access.
  Reinforces: always read *what actually changed* in a plan against a
  live, working resource, not just whether the plan succeeds.
- **`client_key_wo` (write-only) needs an explicit value wired up** —
  leaving it unset while updating other fields on an existing realm
  risks the provider clearing the live secret rather than leaving it
  untouched. Migrated the secret from the original manual setup
  (`proxmox-host/secrets/entraid-oidc.enc.yaml`) into this config via a
  new `~/homelab-env.sh` export, rather than creating a duplicate.
- **App Role assignments target the Service Principal object, not the
  Application Registration** — two distinct objects in Entra ID's model;
  needed importing the existing Service Principal separately.
- **`pveum acl delete` is its own subcommand**, not a `-delete` flag on
  `pveum acl modify` — discovered via `pveum help` after a guess failed.
- **An apparently-clean `tofu plan` meant nothing** at one point in this
  work, because `tofu init` had silently never completed in the new
  directory — no state file existed at all, so the "plan" wasn't
  comparing against reality. Always confirm `tofu state list` shows real
  content, not just that `plan`/`apply` ran without error.

## Consequences
- Closes the ADR-0039 backlog item completely — verified via a genuine
  logout/login test with the old direct grant removed, confirming group
  membership alone grants access.
- Establishes a reusable, documented pattern (`opentofu/entraid/` for
  the Azure side, a dedicated `opentofu/<service>-entraid/` per Proxmox-style
  service for the local side) for wiring up ArgoCD's own OIDC next,
  reusing the already-created `agatha-king-*` groups.
- `station-*` and `mcrn-*` remain reserved, empty groups until their
  respective domains have an actual AAA-capable service to attach them
  to.