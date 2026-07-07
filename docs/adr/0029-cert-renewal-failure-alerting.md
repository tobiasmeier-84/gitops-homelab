# ADR-0029: Explicit alerting on certificate renewal failure

**Status:** Accepted

## Context
cert-manager automatically renews certificates issued via DNS-01 (ADR-0007), but a silent renewal failure (e.g. an expired or revoked Cloudflare API token) currently has no dedicated alert distinct from a certificate actually expiring.

## Decision
Add a specific Prometheus alerting rule on cert-manager's own exposed metrics (e.g. certificate expiry time approaching without a corresponding recent successful renewal event).

## Reasoning
Mirrors the same reasoning already applied to backup failure/staleness alerting — a silently failing automated process is only safe if failure itself is observable, not just the eventual downstream symptom (an expired cert breaking ingress).