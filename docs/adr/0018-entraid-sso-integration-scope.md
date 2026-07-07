# ADR-0018: Entra ID SSO — integration scope

**Status:** Accepted

## Context
A platform-wide requirement: authenticate against Microsoft Entra ID wherever feasible, rather than maintaining separate local credentials per service.

## Decision
Integrate Entra ID via native OIDC where a service supports it directly: Proxmox VE, the Kubernetes API (via `kubelogin`), ArgoCD, Grafana, Harbor, and Nextcloud (via its OIDC app). Services without native OIDC support (Longhorn UI, Prometheus/Alertmanager, HAProxy stats) are covered via an oauth2-proxy layer (ADR-0019) rather than left unauthenticated or given bespoke local credentials.

## Explicitly out of scope
- **GitHub**: SAML/SSO with an external IdP is a GitHub Enterprise Cloud feature, unavailable on free/personal accounts. Local GitHub credentials (protected by the account's own 2FA) remain the access method.
- **Cloudflare dashboard**: SSO is gated behind Cloudflare's paid Zero Trust tier — not justified for a single-user account.
- **Backblaze B2, Hetzner, Bitwarden Secrets Manager, Azure Key Vault**: accessed via API tokens for machine-to-machine calls (backup CronJob, DDNS updater), not interactive human login — SSO doesn't apply to this category of access. Azure Key Vault is a partial exception: access to it is already natively governed by Entra ID RBAC as a property of being an Azure resource.
- **SSH access to cluster nodes**: see ADR-0020 (backlogged).

## Reasoning
Centralizing authentication reduces the number of independent credential stores to secure and rotate, and gives a single point of user lifecycle management (a leaver only needs de-provisioning in one place: Entra ID). Applied only where a service genuinely supports it or where the gap (Longhorn UI's lack of any auth) already needed closing regardless.

## Consequences
Every OIDC-protected service now has an external dependency on Entra ID's availability (`login.microsoftonline.com` reachability) at login time, even for services that are otherwise purely internal/split-horizon. Acceptable given a home internet connection is already assumed elsewhere in this design (e.g. DNS-01 cert issuance, container registry pulls).