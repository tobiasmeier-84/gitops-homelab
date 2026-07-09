# ADR-0035: Naming convention — four thematic tiers under solsys.dev

**Status:** Accepted

## Context
A consistent naming scheme was wanted across every layer of the platform: physical compute hosts, network devices, virtual machines, and application workloads/subdomains, tied to the domain registered for this project (solsys.dev). Names are drawn from *The Expanse*, with each tier's theme chosen to fit the architectural role it names, and workload names further subdivided by faction to reflect what each workload actually does.

## Decision

### Four tiers, one per architectural layer

| Layer | Theme | Items |
|---|---|---|
| Physical compute (Proxmox hosts) | Belt objects (real minor planets/asteroids) | `ceres`, `eros`, `pallas` |
| Network devices | Constructed stations | firewall (RV320) → `tycho`; switches (HPE 1920/1950) → `medina` |
| Virtual layer (VMs) | Saturn moons | HAProxy VM → `titan`; RKE2 nodes → `enceladus`, `mimas`, `rhea`; future VMs → `iapetus`, `dione`, etc. |
| App/workload | Ships, subdivided by faction (see below) | see table |

### App/workload ships, subdivided by faction

Ship faction reflects each workload's actual function, not arbitrary assignment:

| Ship | Faction | Workload | Why this faction |
|---|---|---|---|
| Rocinante | *Independent* (deliberately outside all three factions) | Nextcloud | The main, user-facing application — fittingly crewed by no single power, same as in the source material |
| Canterbury | Belter (working/hauler vessels → background jobs) | Backup CronJob | An ice hauler is itself a background logistics job |
| Pella | Belter | DDNS updater CronJob | Background, unattended, functional |
| Donnager | MCRN (discipline/defense → security workloads) | CrowdSec | Perimeter defense — a show of force at the boundary |
| Scirocco | MCRN | cert-manager | Security/certificate management |
| Karakum | MCRN | oauth2-proxy | Authentication gateway |
| Hammurabi | MCRN | Admission control (Kyverno + cosign signature verification) | Double meaning: Hammurabi's Code is the historical origin of written law — fitting for policy enforcement |
| Agatha King | UN (institutional authority → management/control-plane) | ArgoCD | The UN fleet flagship — fitting for the tool controlling every other workload |
| Arboghast | UN | Harbor | A UN research vessel that investigated the protomolecule — parallels a registry that inspects every image |

### Subdomain structure

All under `solsys.dev`. Internal-only tiers use split-horizon DNS (resolved only by the internal resolver, never published in Cloudflare's public zone) but can still carry real, browser-trusted certificates, since DNS-01 validation only requires a public `TXT` record, never a public `A` record:
belt.solsys.dev     — physical Proxmox hosts (internal only)         e.g. ceres.belt.solsys.dev
station.solsys.dev  — network devices (internal only)                e.g. tycho.station.solsys.dev
orbit.solsys.dev    — virtual layer VMs (internal only)               e.g. titan.orbit.solsys.dev
gate.solsys.dev     — app/workload layer, thematic hostname (public, primary)   e.g. rocinante.gate.solsys.dev
app.solsys.dev      — app/workload layer, functional hostname (public, alias)   e.g. nextcloud.app.solsys.dev
proto.solsys.dev    — prototypes (see below)

Each app-tier service gets both a thematic (`gate`) and functional (`app`) public hostname pointing at the same backend.

The previously separate `mgmt.homelab.internal` domain (used in the Proxmox answer-file template) is retired in favor of `belt.solsys.dev`, consolidating everything under one registered domain.

## Reserved for future use

`proto.solsys.dev` is reserved for prototypes and experimental workloads (a deliberate double meaning: Protomolecule / prototype). Individual prototypes are named after **Jupiter's moons** (`europa.proto.solsys.dev`, `ganymede.proto.solsys.dev`, etc.) — Jupiter has 95 known moons, providing effectively unlimited headroom for however many prototypes accumulate over time.

**Earth and Mars are reserved naming space with no assigned meaning yet.** No subdomain, environment, or architectural concept is mapped to either at this time — held in reserve for a future use not yet identified, rather than forced into a mapping now. Revisit when a concrete need arises (e.g. a genuine staging environment, a second physical site, or something not yet anticipated).

## Reasoning

- **Belt objects vs. Stations** distinguishes the raw physical substrate (natural asteroids, i.e. the compute hosts themselves) from constructed infrastructure built to serve a function (network devices) — a clean conceptual split that also avoids name collisions between the two physical-layer categories.
- **Saturn moons over Mars** for the virtual layer: Mars has only 2 moons, an immediate ceiling; Saturn has 80+, providing headroom as VMs are added over time.
- **Ships for workloads, subdivided by faction**: rather than assigning ship names arbitrarily, each faction's real characteristics in the source material (Belters as working-class haulers, Mars as disciplined/militaristic, Earth/UN as institutional authority) map onto genuinely distinct categories of workload (background jobs, security, management) — giving the naming scheme actual internal logic rather than decoration.
- **Subdomain labels match their tier's theme name directly** (`belt`, `station`, `orbit`) rather than generic technical terms (the originally used `host`/`net` were replaced for exactly this reason) — internal-only tiers have no professional-URL constraint, so full thematic commitment costs nothing.
- **"Gate" over "Ring"** (originally considered) avoids reusing a singular, unique proper noun (there is only one Ring in the setting) as a generic category label for many different services.
- **DNS-01 certificate issuance doesn't require public A records**, so even the fully internal-only tiers can carry real, browser-trusted Let's Encrypt certificates rather than self-signed ones, despite never being resolvable outside the internal network.

## Consequences

- One `Certificate` resource with six wildcard SANs (`*.belt`, `*.station`, `*.orbit`, `*.gate`, `*.app`, `*.proto`, all `.solsys.dev`) covers every tier via a single DNS-01 validation flow.
- The Proxmox answer-file template's `fqdn` field and `nodes.yaml` hostnames use `ceres`/`eros`/`pallas` on `belt.solsys.dev`, replacing the earlier generic `pve1`/`pve2`/`pve3` placeholders and the retired `homelab.internal` domain.
- Internal DNS (the home router/internal resolver) must be configured to resolve `*.belt.solsys.dev`, `*.station.solsys.dev`, and `*.orbit.solsys.dev` to internal IPs — these records deliberately do not exist in Cloudflare's public-facing zone.
- Reassigning a ship name to a different workload later (e.g. if Donnager's role changes) is a documentation update only — no technical dependency is tied to the name itself.