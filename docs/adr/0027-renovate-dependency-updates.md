# ADR-0027: Automated dependency updates via Renovate

**Status:** Accepted

## Context
Every Helm chart version and container image tag in the GitOps repo is pinned (deliberately, for reproducibility) but pinned versions go stale silently without an active update mechanism.

## Decision
Run Renovate (as a GitHub App or scheduled Action) against the repo, opening automated PRs for Helm chart and container image version bumps.

## Reasoning
"Everything reconstructable and pinned in git" is only a good property if the pinned versions are also current — otherwise pinning just becomes a slow-motion accumulation of unpatched CVEs. Renovate PRs go through the same CI validation (kubeconform, etc.) as any other change before merge.

## Consequences
Regular PRs to review and merge; some noise-management needed (grouping, scheduling) to keep this from becoming overwhelming on a single-maintainer repo.