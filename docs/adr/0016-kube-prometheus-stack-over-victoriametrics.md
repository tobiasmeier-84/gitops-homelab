# ADR-0016: Monitoring stack — kube-prometheus-stack over VictoriaMetrics

**Status:** Accepted

## Context
kube-prometheus-stack (Prometheus + Grafana + Alertmanager) is the de facto standard Kubernetes monitoring stack. VictoriaMetrics is a Prometheus-compatible alternative with a meaningfully lower resource footprint — relevant given the 4-core/8-thread CPUs on each node.

## Decision
kube-prometheus-stack.

## Reasoning
It's the stack most commonly referenced in platform-engineering job postings and interviews, making it the more valuable thing to have hands-on experience operating for this repo's stated purpose. The resource-footprint advantage VictoriaMetrics offers is real, but retention/scrape-interval tuning (already a planned decision — see decision log) is expected to keep kube-prometheus-stack within budget on this hardware.

## Consequences
Higher baseline resource usage than VictoriaMetrics would require. If CPU pressure becomes a real operational problem, VictoriaMetrics (or trimming Prometheus's own scrape frequency/retention further) is the mitigation path to revisit.
