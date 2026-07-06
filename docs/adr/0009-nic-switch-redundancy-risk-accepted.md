# ADR-0009: NIC / switch redundancy — risk accepted, revisit possible

**Status:** Accepted risk (backlogged)

## Context
Each node has a single 10G NIC (dual-port on one physical card); two 10G-capable switches are available but not yet wired for redundancy.

## Decision
Accept the single-card-as-single-point-of-failure risk for the initial build; true redundancy is deferred to the backlog rather than solved at initial build time.

## Reasoning
The physical capability for redundancy already exists (2 switches, a dual-port card), so this is a configuration task deferred for scheduling reasons, not a hardware gap accepted permanently. Fixing it now would delay the rest of the build for a failure mode that is both survivable (nodes degrade to 1G connectivity rather than a full outage) and comparatively unlikely relative to other risks in this document.

## Consequences
A failure of the 10G card on any node degrades that node to 1G connectivity rather than causing a full outage. Revisit once the core platform is stable.
