# ADR-0026: Resource requests/limits and per-namespace ResourceQuotas

**Status:** Accepted

## Context
Each node has only 4 cores/8 threads. Without explicit resource requests/limits, one workload (e.g. Harbor's vulnerability scanning, or Loki under heavy log volume) can starve others under CPU/memory pressure.

## Decision
Set explicit resource requests and limits on every workload, and define per-namespace ResourceQuotas as a backstop against any single namespace consuming disproportionate cluster resources.

## Reasoning
Given the tight CPU budget already flagged multiple times in this design (monitoring stack sizing, Harbor's overhead), deliberate resource boundaries are necessary, not optional — this is the mechanism that actually enforces the intent behind those earlier sizing conversations.

## Consequences
Requires tuning per workload rather than accepting defaults; some initial trial-and-error to find values that don't cause OOM-kills or excessive throttling on this hardware.