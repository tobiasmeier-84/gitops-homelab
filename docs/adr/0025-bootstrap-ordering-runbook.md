# ADR-0025: Explicit first-boot bootstrap ordering runbook

**Status:** Accepted

## Context
The platform has several near-circular-looking dependencies (e.g. ArgoCD manages Harbor via GitOps, but needs to pull its own container image from a registry before Harbor exists) that have never been written down as an explicit sequence.

## Decision
Document the exact bootstrap order as a runbook: state backend (ADR-0024) → Proxmox answer-file install → OpenTofu VM provisioning → Ansible base config/RKE2/Longhorn → ArgoCD manual bootstrap (pulling from a public registry, not yet Harbor) → GitOps takeover of everything else, including Harbor itself → optional cutover of subsequent image pulls to Harbor once it's running.

## Reasoning
Makes explicit what was previously only implicit in scattered decisions across this design conversation — a rebuild (or a reviewer) shouldn't have to reconstruct the correct order from first principles.