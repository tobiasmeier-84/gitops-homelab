# ADR-0023: Tested, end-to-end disaster-recovery runbook

**Status:** Accepted

## Context
The repo's governing principle claims full reconstructability from git alone, but this has never actually been exercised end to end — it's currently an aspirational claim, not a verified capability.

## Decision
Write and actually execute a full disaster-recovery runbook: from bare Proxmox hosts (answer-file install) through OpenTofu provisioning, Ansible configuration, ArgoCD bootstrap, and backup restoration, documenting each step and any manual intervention required.

## Reasoning
An untested claim of reconstructability is a hypothesis, not a fact — the same reasoning already applied to backups specifically (see the restore-drills decision in the observability layer) extended to the whole platform. This is also one of the strongest possible portfolio artifacts: a genuinely executed, documented DR exercise is far more credible than a design that merely permits one.