# ADR-0006: Backup orchestration — Kubernetes CronJob over Argo Workflows

**Status:** Accepted

## Context
The backup procedure (ADR-0005) needs a scheduler/orchestrator inside the cluster.

## Options considered
- Kubernetes CronJob + shell script
- Argo Workflows

## Decision
A plain Kubernetes CronJob running a shell script.

## Reasoning
The backup procedure is a linear sequence with two independent branches at the end — it has no branching complexity, per-step conditional retries, or need for DAG visualization that would justify a dedicated workflow engine. A CronJob is also more representative of how backup automation is typically run in production platform teams, and avoids adding another controller to secure and maintain.

## Consequences
If the pipeline's complexity grows substantially (e.g. many more PVCs with different handling logic), this decision should be revisited.
