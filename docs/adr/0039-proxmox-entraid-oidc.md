# ADR-0039: Proxmox Entra ID OIDC integration — implementation

**Status:** Accepted

## Context
ADR-0018 scoped Entra ID SSO for Proxmox VE among other services. This ADR captures the concrete implementation: reusing the existing `toebel.ch` tenant (rather than a separate tenant, per the earlier B2-account-style trade-off discussion), with `solsys.dev` added as a verified custom domain.

## Decision
- **Single-tenant** App Registration ("Accounts in this organizational directory only") — no external or personal Microsoft accounts can authenticate.
- Redirect URIs registered for all 3 node hostnames (`https://ceres.belt.solsys.dev:8006`, `https://eros.belt.solsys.dev:8006`, `https://pallas.belt.solsys.dev:8006`), since the web UI is reachable at any node individually.
- Proxmox OIDC realm (`entraid`) configured with `--autocreate 1` and `--username-claim preferred_username`, but **not set as the default realm** — PAM (existing username/password login) remains the default/fallback, deliberately, until OIDC is fully proven reliable.
- **Authorization**: for now, the specific admin user was granted the `Administrator` role directly (`pveum aclmod / -user <user>@entraid -role Administrator`), rather than the group-based mapping ADR-0021 specifies. This is a known, deliberate interim step — see Consequences.

## Reasoning
Keeping PAM as the default/fallback avoids a repeat of the exact failure mode that would lock out access if OIDC misconfiguration ever recurred mid-session (as happened multiple times during initial setup — invisible Unicode characters from Azure Portal copy-paste, and a tenant-ID/client-ID mismatch). Direct per-user authorization unblocks real usage immediately without waiting on the more involved group-claim configuration.

## Consequences
- **Backlogged**: proper group-based authorization mapping (an Entra ID security group, e.g. `pve-admins`, mapped to the Proxmox role via a configured groups claim) instead of the current direct per-user grant. The direct grant works but doesn't scale — a second admin currently requires another manual `pveum aclmod`, not just adding them to a group. See `docs/BACKLOG.md`.
- See `proxmox-host/README.md` for the full setup procedure and troubleshooting (tenant mismatches, invisible-character copy-paste issues).