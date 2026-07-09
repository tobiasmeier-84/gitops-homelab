# ADR-0035: Naming convention — four thematic tiers under solsys.dev

**Status:** Accepted

## Context
A consistent naming scheme was wanted across every layer of the platform: physical compute hosts, network devices, virtual machines, and application workloads/subdomains, tied to the domain registered for this project (solsys.dev).

## Decision
Four thematic tiers, each mapped to one architectural layer, all real or fictional elements grounded in *The Expanse*:

| Layer | Theme | Items |
|---|---|---|
| Physical compute (Proxmox hosts) | Belt objects (real minor planets/asteroids) | `ceres`, `eros`, `pallas` |
| Network devices | Constructed stations | firewall (RV320) → `tycho`; switches (HPE 1920/1950) → `medina` |
| Virtual layer (VMs) | Saturn moons | HAProxy VM → `titan`; RKE2 nodes → `enceladus`, `mimas`, `rhea`; future VMs → `iapetus`, `dione`, etc. |
| App/workload | Ships | Nextcloud → `rocinante`; monitoring → `donnager`; ArgoCD → `nauvoo`; Harbor → `razorback`; backup job → `canterbury` |

Subdomain structure, all under `solsys.dev`:
host.solsys.dev    — physical Proxmox hosts (internal only, split-horizon)
net.solsys.dev     — network devices (internal only, split-horizon)
orbit.solsys.dev   — virtual layer VMs (internal only, split-horizon)
gate.solsys.dev    — app/workload layer, thematic public hostname (primary)
app.solsys.dev     — app/workload layer, functional public hostname (alias)

Each app-tier service gets both a thematic (`gate`) and functional (`app`) hostname pointing at the same backend, e.g. `rocinante.gate.solsys.dev` and `nextcloud.app.solsys.dev` both resolve to Nextcloud.

The previously separate `mgmt.homelab.internal` domain (used in the Proxmox answer-file template) is retired in favor of `host.solsys.dev`, consolidating everything under one registered domain.

## Reasoning
- **Belt objects vs. Stations** distinguishes the raw physical substrate (natural asteroids, i.e. the compute hosts themselves) from constructed infrastructure built to serve a function (network devices) — a clean conceptual split that also avoids name collisions between the two physical-layer categories.
- **Saturn moons over Mars** for the virtual layer: Mars has only 2 moons, an immediate ceiling; Saturn has 80+, providing headroom as VMs are added over time.
- **Ships for workloads**: ships carry cargo and do work, a fitting metaphor for application workloads specifically, as distinct from the infrastructure layers beneath them.
- **"Gate" over "Ring"** (the originally considered name) avoids reusing a singular, unique proper noun (there is only one Ring in the setting) as a generic category label for many different services.
- **DNS-01 certificate issuance doesn't require public A records**, so even the fully internal-only tiers (`host`, `net`, `orbit`) can carry real, browser-trusted Let's Encrypt certificates rather than self-signed ones, despite never being resolvable outside the internal network.

## Consequences
- One `Certificate` resource with five wildcard SANs (`*.host`, `*.net`, `*.orbit`, `*.gate`, `*.app`, all `.solsys.dev`) covers every tier via a single DNS-01 validation flow.
- The Proxmox answer-file template's `fqdn` field and `nodes.yaml` hostnames are updated to use `ceres`/`eros`/`pallas` on `host.solsys.dev`, replacing the earlier generic `pve1`/`pve2`/`pve3` placeholders and the retired `homelab.internal` domain.
- Internal DNS (the home router/internal resolver) must be configured to resolve `*.host.solsys.dev`, `*.net.solsys.dev`, and `*.orbit.solsys.dev` to internal IPs — these records deliberately do not exist in Cloudflare's public-facing zone.