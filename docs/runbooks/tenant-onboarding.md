# Runbook: Onboarding a new Crew tenant

Deliberately manual, owner-performed — see ADR-0042's reasoning: identity
and trust provisioning is a human-judgment decision, not something a
tenant's own git commits should be able to trigger. Once this runbook is
complete, everything else (deploying, updating, adding hostnames once
`external-dns` exists) is genuinely self-service via git, per ADR-0046.

## Prerequisites
- The tenant's app has a name — pick a fitting Expanse ship (any
  faction), following the same exercise as every other workload in this
  project (see ADR-0035). This becomes `<shipname>` throughout.
- The tenant has their own git repository ready (self-service pattern
  is repo-per-tenant, per ADR-0042's decision on option (a)).

## 1. Create the Entra ID groups (OpenTofu, `opentofu/entraid/`)

Add to the `rbac_domains` list alongside the existing `belt`,
`agatha-king`, `station`, `mcrn`:
```hcl
rbac_domains = ["belt", "agatha-king", "station", "mcrn", "<shipname>"]
```
This automatically creates `<shipname>-captain`, `<shipname>-crew`,
`<shipname>-passenger` via the existing `for_each` logic — no new
resource blocks needed.

```bash
cd opentofu/entraid
tofu plan   # confirm only the 3 new <shipname>-* groups are being added
tofu apply
```

## 2. Add the tenant as Captain of their own group

```hcl
data "azuread_user" "tenant_<shipname>" {
  user_principal_name = "<their UPN or invited guest UPN>"
}

resource "azuread_group_member" "tenant_<shipname>_captain" {
  group_object_id  = azuread_group.rbac["<shipname>-captain"].object_id
  member_object_id = data.azuread_user.tenant_<shipname>.object_id
}
```
```bash
tofu apply
```

If they're an external guest (not yet in the tenant), invite them first
via the Entra ID portal (free under the B2B guest tier — no license
needed for basic guest invites), then reference their resulting UPN here.

## 3. Create the AppProject (ArgoCD)

New file: `gitops/manifests/argocd-projects/<shipname>.yaml`
```yaml
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: <shipname>
  namespace: argocd
spec:
  sourceRepos:
    - "https://github.com/<tenant-github-username>/<their-repo>.git"
  destinations:
    - namespace: <shipname>
      server: https://kubernetes.default.svc
  clusterResourceWhitelist: []
```
`clusterResourceWhitelist: []` keeps them genuinely walled into their
own namespace — no cluster-scoped resources at all.

## 4. Add the RBAC policy mapping (Ansible, `argocd-oidc` role)

Add to `templates/argocd-rbac-cm.yaml.j2`:

p, role:<shipname>-captain, applications, , <shipname>/, allow
p, role:<shipname>-captain, logs, get, <shipname>/*, allow
p, role:<shipname>-captain, repositories, get, *, allow

g, <shipname>.captain, role:<shipname>-captain

(a `-crew` variant can be added later, with narrower permissions, if the
tenant wants to delegate limited access within their own sandbox — not
needed at initial onboarding)

```bash
cd ansible
ansible-playbook site.yml --diff --limit rke2_nodes
```

## 5. Confirm

- Tenant logs into ArgoCD via SSO, confirms they see only their own
  `<shipname>` project/namespace, nothing else
- Tenant pushes a test `Application` pointer to their own repo,
  confirms it syncs successfully into their own namespace only

## Ongoing: adding a second app for the same tenant

Only step 3 (a new AppProject) and step 4 (a new RBAC policy block) are
needed — their Entra ID identity and Captain group membership are
already established from onboarding and don't need repeating.