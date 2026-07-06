# ADR-0003: GitOps delivery — ArgoCD, app-of-apps

**Status:** Accepted

## Context
All workload configuration must be reconstructable from git; a mechanism is needed to continuously reconcile the live cluster against the repo.

## Decision
ArgoCD, with a single root Application (`gitops/bootstrap/`) pointing at a repo folder of per-workload Application manifests (`gitops/apps/*`).

## Reasoning
A single git commit becomes the source of truth for the whole cluster's workload state. ArgoCD itself is stateless — its state is git plus the live cluster — so it needs no special handling to survive a node failure.

## Consequences
`syncPolicy.automated.selfHeal: true` is enabled so ArgoCD corrects manual drift automatically, including after a node rebuild-and-rejoin.
