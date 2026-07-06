# ADR-0001: Kubernetes distribution — RKE2

**Status:** Accepted

## Context
An existing k3s cluster already exists from prior study work. A new, separate cluster is needed for production workloads (Nextcloud and similar).

## Options considered
- k3s (again)
- Vanilla Kubernetes (kubeadm)
- RKE2

## Decision
RKE2.

## Reasoning
- Reusing k3s teaches nothing new, and k3s's simplifications (SQLite-oriented defaults, Traefik ingress, trimmed-down feature set) hide operational details a production-intent cluster should surface.
- Vanilla kubeadm demands the most manual operational overhead (cert rotation, CNI/ingress selection, upgrade tooling) for the least differentiation.
- RKE2 ships CIS-hardened defaults (PodSecurity admission, encrypted secrets at rest, audit logging), bundles ingress-nginx (the most commonly deployed ingress controller in production, unlike k3s's Traefik default), and stays closer to upstream Kubernetes behavior than k3s.

## Consequences
More operational surface than k3s (etcd/HA understanding is now explicit, not hidden), but a stronger, more transferable signal for platform-engineering work.
