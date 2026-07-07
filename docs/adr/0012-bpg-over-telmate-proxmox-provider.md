# ADR-0012: OpenTofu Proxmox provider — bpg/proxmox over telmate/proxmox

**Status:** Accepted

## Context
Two community OpenTofu/Terraform providers exist for Proxmox: `bpg/proxmox` and `telmate/proxmox`.

## Decision
`bpg/proxmox`.

## Reasoning
More actively maintained and better Proxmox API coverage than `telmate/proxmox`, which is the older, more widely-tutorialized option but has a much slower release cadence.

## Consequences
Less third-party tutorial content to lean on if something goes wrong — official provider documentation is the primary reference.
