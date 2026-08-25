# ADR-0050: Require Entra ID App Role assignment on every Service Principal

**Status:** Accepted

## Context
While reviewing Rocinante's (Nextcloud) OIDC setup, a real authorization
gap was discovered: assigning security groups to App Roles (the pattern
used throughout this project — `belt-*`, `agatha-king-*`, `rocinante-*`,
etc.) controls what *claims* a successfully-issued token carries. It
does **not**, by itself, control *who is allowed to authenticate at
all*. These are two separate gates in Entra ID's model, and only the
first had been configured anywhere in this project.

Confirmed via the live provider config: `"restrictLoginToGroups":false`
on Nextcloud's OIDC provider, and no `app_role_assignment_required`
setting anywhere in `opentofu/entraid/main.tf`'s Service Principal
resources. Practical effect: **any user in the tenant** — not just
those in a relevant `*-captain`/`*-crew`/`*-passenger` group — could
complete the OIDC login flow and reach whatever each app does with an
unrecognized/empty `roles` claim.

## Real risk per affected app, at time of discovery
- **Rocinante (Nextcloud)** — highest risk: any tenant user got a full
  account auto-provisioned via `user_oidc`, no fallback deny.
- **Agatha King (ArgoCD)** — also genuinely concerning:
  `policy.default: role:passenger-default` meant any successful login
  granted read-only visibility into the entire infrastructure (every
  Application, its config, sync status), zero group membership
  required.
- **Proxmox** — lower risk: an unmapped user could authenticate but
  Proxmox's own ACLs mean they'd land with genuinely zero permissions.
- **Pomerium** — lowest risk: its own policies explicitly require
  `claim/roles` to match a specific value, so an unmapped user was
  already actively denied by the policy engine, not just left with
  minimal access.

## Decision
Set `app_role_assignment_required = true` on all four Service
Principals (`proxmox_homelab`, `argocd`, `pomerium`, `nextcloud`) in
`opentofu/entraid/main.tf`. This moves the authorization check to the
correct layer — Entra ID itself refuses to issue a token at all to a
user with no App Role assignment on that specific application,
stopping unauthorized users before they ever reach the app, rather than
after.

```hcl
resource "azuread_service_principal" "nextcloud" {
  client_id                    = azuread_application.nextcloud.client_id
  app_role_assignment_required = true
}
# ...same pattern for proxmox_homelab, argocd, pomerium
```

## Verification
Confirmed with a real test identity, not assumed: the `test-crew`
guest account was denied login to Nextcloud entirely until explicitly
added to `rocinante-passenger` — at which point login succeeded
cleanly. Genuine end-to-end proof, not a configuration read.

One nuance worth recording: **the operator's own account was not a
valid test** for this restriction, despite still being able to log in
before the gap was fixed — Global Administrator accounts have an
implicit bypass of `app_role_assignment_required` within their own
tenant, a documented Entra ID behavior, not a flaw in this fix. Testing
authorization restrictions always requires a genuinely non-privileged
identity, never the admin account itself.

## Consequences
- **This must be part of the standard pattern for every future app**
  added to this project's Entra ID integration — not an optional
  hardening step. The tenant onboarding runbook
  (`docs/runbooks/tenant-onboarding.md`) should be updated to include
  this setting explicitly for any new Crew tenant's own App
  Registration too.
- The operator's own account needed explicit `rocinante-captain`
  membership added — it had been missed when Rocinante's RBAC was
  originally built, only surfacing once this restriction was tested
  properly with a non-admin identity.