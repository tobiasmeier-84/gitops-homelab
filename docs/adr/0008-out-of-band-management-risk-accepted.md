# ADR-0008: Out-of-band management — risk accepted

**Status:** Accepted risk

## Context
Cluster hardware is repurposed, low-cost decommissioned client machines (i7-7700), not server-grade hardware with IPMI/iLO support.

## Decision
No out-of-band management. If a node hangs, recovery requires physical access.

## Reasoning
Adding IPMI-capable hardware or a PDU-based remote power solution is a real cost that isn't justified for a home-lab environment where physical access to the hardware is always available, if inconvenient.

## Consequences
A hung node requires a manual, on-site power cycle. Acceptable given the hardware's origin and the lab's context; would be revisited if the hardware were ever relocated somewhere without easy physical access.
