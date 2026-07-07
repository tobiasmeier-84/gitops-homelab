# ADR-0019: oauth2-proxy in front of services without native OIDC support

**Status:** Accepted

## Context
Longhorn UI, the Prometheus/Alertmanager UI, and the HAProxy stats page have no built-in authentication of their own — Longhorn UI in particular is currently unauthenticated by default, an existing gap independent of the Entra ID requirement.

## Decision
Deploy oauth2-proxy in front of each of these, configured against Entra ID as the OIDC provider, rather than leaving them open or inventing bespoke local credentials.

## Reasoning
This closes a real pre-existing security gap (unauthenticated Longhorn UI) as a direct side effect of the broader Entra ID requirement, using one consistent mechanism rather than three different one-off solutions.

## Consequences
One more component to deploy and keep patched per protected service (or one shared oauth2-proxy instance handling multiple upstreams, depending on final implementation). Each of these UIs' login now also depends on Entra ID reachability, consistent with ADR-0018.