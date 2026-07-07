# ADR-0013: CNI — Canal over Cilium

**Status:** Accepted

## Context
RKE2 ships Canal (Flannel + Calico) as its default CNI. Cilium is a common eBPF-based alternative with stronger NetworkPolicy enforcement and built-in network observability.

## Decision
Keep Canal, RKE2's default.

## Reasoning
Canal already satisfies the NetworkPolicy requirement (default-deny per namespace, see decision log) without adding a new component to learn and operate. Cilium's eBPF-based observability is a genuine capability this setup forgoes, but at this cluster's scale and traffic complexity, the added operational surface isn't justified.

## Consequences
No eBPF-based network observability (e.g. Hubble). If deep network-flow visibility becomes a real need later, this is the natural upgrade path — revisit then rather than now.
