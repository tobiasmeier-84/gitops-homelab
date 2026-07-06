# ADR-0007: DNS & certificate issuance — Cloudflare, DNS-01, CronJob DDNS updater

**Status:** Accepted

## Context
Internal DNS is provided by the home router with split-horizon resolution. The router's native DynDNS integration has no API cert-manager can use for DNS-01 challenges.

## Decision
Migrate the domain's authoritative DNS to Cloudflare. Use cert-manager's native DNS-01 solver against the Cloudflare API. Handle the dynamic public IP problem separately via a Kubernetes CronJob that checks the current public IP and updates the Cloudflare `A` record via API when it changes.

## Reasoning
DNS-01 challenges only require creating a `TXT` record and are independent of whether the `A` record is current — this decouples certificate issuance from the dynamic-IP problem entirely. cert-manager has first-class Cloudflare support with no separate webhook to maintain. The DDNS updater reuses the same CronJob + SOPS-secret pattern already established for backups (ADR-0005, ADR-0006), rather than introducing a third tool.

## Consequences
A Cloudflare API token (scoped to a single zone) becomes another SOPS-encrypted secret. Valid, publicly-trusted certificates can be issued for names that only ever resolve internally, with zero internet exposure of the ingress required.
