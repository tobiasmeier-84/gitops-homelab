# ADR-0028: External dead-man's-switch monitoring

**Status:** Accepted

## Context
Alertmanager can detect problems Prometheus observes from inside the cluster, but has no way to alert if the entire home network, internet connection, or the monitoring stack itself goes down — the observer and the observed fail together.

## Decision
Configure a free third-party heartbeat/dead-man's-switch service (e.g. a periodic authenticated ping from inside the cluster to an external uptime-check provider) that alerts via a separate channel (e.g. email) if the heartbeat stops arriving.

## Reasoning
This is the one category of failure the entire rest of the observability stack is structurally blind to — monitoring the monitors requires a genuinely external vantage point.

## Consequences
Introduces a dependency on a third-party free-tier service for this specific check; low risk given it's supplementary to, not a replacement for, the internal monitoring stack.