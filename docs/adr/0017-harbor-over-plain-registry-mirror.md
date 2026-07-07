# ADR-0017: Container registry cache — Harbor over a plain pull-through mirror

**Status:** Accepted

## Context
A pull-through registry cache removes internet access as a dependency for routine pod restarts/node reboots. The plain `registry:2` image provides pull-through caching alone; Harbor adds vulnerability scanning, a web UI, and project/role-based access control on top of the same core capability.

## Decision
Harbor.

## Reasoning
Vulnerability scanning of cached images is a meaningful security-maturity signal for this repo's stated purpose, and the web UI gives a demonstrable, walkable artifact (similar reasoning to the ArgoCD-over-Flux choice) rather than a purely backend service with nothing to show.

## Consequences
Harbor is a substantially heavier component to operate than a plain registry mirror (its own database, more memory footprint, more to patch/monitor) — a real cost on already CPU-constrained nodes. Worth watching resource usage closely once deployed; the plain mirror remains a fallback if Harbor's footprint proves too heavy in practice.
