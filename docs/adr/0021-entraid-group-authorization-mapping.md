# ADR-0021: Authorization — Entra ID group mapping to RBAC

**Status:** Accepted

## Context
OIDC authentication (ADR-0018) confirms identity but not permissions. Without an explicit authorization mapping, services either grant no access post-login (safe but unusable) or default to over-privileged access.

## Decision
Define Entra ID security groups (e.g. `k8s-admins`, `k8s-viewers`) and map them explicitly:
- **Kubernetes**: `ClusterRoleBinding`/`RoleBinding` resources binding Entra ID group claims (via the OIDC groups claim) to Kubernetes RBAC roles.
- **ArgoCD**: its own RBAC config (`argocd-rbac-cm`) mapping the same Entra ID groups to ArgoCD roles (admin, read-only, per-project).
- **Harbor**: OIDC group-to-project-role mapping in Harbor's own authentication settings.

## Reasoning
Each of these three systems has its own independent RBAC model — OIDC login alone doesn't propagate permissions between them. Explicit, git-committed group-to-role mappings keep authorization declarative and auditable, consistent with the rest of this repo's GitOps approach.

## Consequences
Entra ID group membership changes require a corresponding (git-committed) mapping to exist for new groups; a new group with no mapping defaults to no access, which is the safe failure mode.