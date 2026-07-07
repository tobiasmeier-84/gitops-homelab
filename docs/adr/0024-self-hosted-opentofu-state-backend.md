# ADR-0024: OpenTofu remote state backend — self-hosted, bootstrapped first

**Status:** Accepted

## Context
A remote state backend is preferable to local state (enables native encryption, avoids a single laptop being a single point of failure for infrastructure state) but creates a bootstrap ordering problem: the backend itself needs infrastructure that doesn't yet exist when OpenTofu first runs.

## Decision
Stand up a minimal self-hosted remote backend (e.g. a small MinIO instance) as the very first piece of infrastructure, provisioned manually or via a minimal separate OpenTofu configuration with local state, before the main OpenTofu configuration (for the RKE2 VMs) is run against it.

## Reasoning
Breaks the circular dependency cleanly: a small, separately-tracked bootstrap step (local state, minimal footprint) creates the backend that everything else then uses. This mirrors the same "someone/something has to be first" pattern already accepted for ArgoCD's own bootstrap (manual Ansible install, then GitOps takes over).

## Consequences
One piece of infrastructure (the state backend itself) is provisioned outside the main GitOps flow and tracked with local state — this is documented explicitly as the one accepted exception, not a silent gap.