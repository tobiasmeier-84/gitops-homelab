# ADR-0011: GitOps engine — ArgoCD over Flux

**Status:** Accepted

## Context
Both ArgoCD and Flux are CNCF-graduated GitOps engines with broadly equivalent core capability (continuous reconciliation of cluster state from git).

## Decision
ArgoCD.

## Reasoning
- ArgoCD's web UI is a genuine advantage for a portfolio project meant to be demoed and discussed — it gives a visual, walkable representation of sync status, application health, and drift, which is useful in an interview setting in a way Flux's more API/CLI-driven model isn't.
- ArgoCD appears more frequently in job postings for this kind of platform-engineering role than Flux does, making it the more transferable skill to demonstrate.
- Flux's lighter operational footprint is a real advantage in the abstract, but doesn't outweigh the above for this repo's specific purpose.

## Consequences
None of Flux's advantages (lower resource usage, more Kubernetes-native CRD design) are captured here — an acceptable trade given the project's goals.
