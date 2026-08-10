# CLAUDE.md

Context for Claude Code working in this repository. See `README.md` for
the full stack overview and `docs/architecture-decisions.md` +
`docs/adr/` for every design decision and its reasoning.

## What this project is

A production-intent Kubernetes home-lab platform (3-node Proxmox cluster,
OpenTofu, Ansible, ArgoCD, eventually RKE2 + Nextcloud + monitoring),
built as a public portfolio piece for platform-engineering job
applications. Domain: `solsys.dev`. Everything is meant to be
reconstructable from this git repository alone.

## Hard rules — do not violate these without explicit, per-instance permission

- **Never run SSH commands** against any host (`ceres`, `eros`, `pallas`,
  `iapetus`, or any future node). Propose the command; the user runs it
  and reports back the result.
- **Never run `tofu apply`, `tofu import`, `tofu state` mutations, or any
  other command that changes real infrastructure.** `tofu plan` is fine
  (read-only). Same rule for any `zpool`/`pvenode`/`pveum` command.
- **Never `git commit` or `git push`** without the user explicitly asking
  for it in that specific instance — not "once things look done," every
  single time.
- These rules exist because this project has real hardware and live
  services behind it (several near-misses already happened this way —
  see `docs/BACKLOG.md` and the git log for examples).

## Before making changes

1. Read `docs/architecture-decisions.md` for the full decision log.
2. Check `docs/BACKLOG.md` — many gaps are already known and tracked;
   don't rediscover them as new problems.
3. Read the specific directory's own `README.md` before touching it —
   most `opentofu/*/` directories have setup instructions, known
   gotchas, and troubleshooting notes specific to that piece.

## Naming convention (see ADR-0035 for full reasoning)

Four tiers, all *Expanse*-themed:

| Layer | Theme | Examples |
|---|---|---|
| Physical Proxmox hosts | Belt objects | `ceres`, `eros`, `pallas` |
| Network devices | Stations | `tycho` (firewall), `medina`/`anderson` (switches), `baragaon` (UPS) |
| VMs | Saturn moons | `titan` (HAProxy), `enceladus`/`mimas`/`rhea` (RKE2 nodes), `iapetus` (MinIO) |
| App/workload, by faction | Ships | Belter=background jobs (`canterbury`, `pella`), MCRN=security (`donnager`, `scirocco`, `karakum`, `hammurabi`), UN=management (`agatha_king`, `arboghast`), independent (`rocinante`=Nextcloud) |

Storage pools also follow this: `razorback`/`tachi`/`canterbury` (ships,
not the earlier rejected `epstein`/`hold` — see ADR-0035's amendment).

Subdomains: `belt.solsys.dev`/`station.solsys.dev`/`orbit.solsys.dev`
(internal-only, split-horizon), `gate.solsys.dev`/`app.solsys.dev`
(public, thematic/functional pair), `proto.solsys.dev` (prototypes,
Jupiter-moon names).

## Hard-won technical lessons — don't repeat these mistakes

- **Always verify provider resource/attribute names against the live
  schema before writing config.** This repo has been burned repeatedly by
  guessing from documentation or general knowledge:
```bash
  tofu providers schema -json | jq '.provider_schemas["registry.opentofu.org/<namespace>/<provider>"].resource_schemas["<resource>"]'
```
  Real examples that went wrong: `proxmox_virtual_environment_node_disk_zfs`
  doesn't exist, it's `proxmox_node_disk_zfs`; `raid_level` doesn't exist,
  it's `raidlevel`; `network_device` is a nested *attribute* (needs
  `= [{ ... }]` syntax with every field present, `null` for unset ones),
  not a classic block.
- **Disk and NIC identifiers (`/dev/sdX`, `/dev/nvmeXnY`) are not stable
  across boots or hardware changes.** Always re-verify with
  `ls -l /dev/disk/by-id/` in the *same session* as any operation that
  depends on them — never reuse a listing from an earlier session or a
  different node.
- **MinIO has no HTTP fallback once TLS is configured.** Every client,
  including same-VM tools, must use `https://iapetus.orbit.solsys.dev:9000`
  — never `http://` or `localhost` (the cert doesn't cover `localhost`,
  and there's no plain-HTTP listener to fall back to).
- **`null_resource` provisioners have no drift detection.** Unlike typed
  resources, OpenTofu never checks whether the real thing they created
  still exists. If real infrastructure is destroyed out-of-band (e.g. a
  disk swap wiping a zpool), `tofu plan` will show "no changes" even
  though reality has diverged — use `tofu apply -replace='<resource>'`
  to force a genuine recreate. Also: masked failures are possible — a
  provisioner script can report success even when an underlying command
  (e.g. `zpool create`) actually failed, if exit codes aren't checked
  explicitly.
- **`.gitignore` blanket-excludes `*.tfvars`, with `!terraform.tfvars`
  overriding it** — `terraform.tfvars` itself is treated as non-secret,
  committed config in this repo (hardware IDs, tenant IDs, etc.), never
  actual credentials. Actual secrets go through SOPS (`secrets/*.enc.yaml`)
  and are exported via `~/homelab-env.sh` (outside the repo, not tracked).
- **Every credential gets its own dedicated, narrowly-scoped token/key** —
  never reuse one credential across purposes (separate Cloudflare tokens
  for Proxmox ACME vs. MinIO ACME vs. the general-purpose Cloudflare
  OpenTofu provider; separate B2 keys for the management provider vs. the
  state-backup script, etc.).
- **A resource's effective permissions can never exceed its owning
  user/principal's permissions**, even if the resource itself is granted
  broader access directly (learned the hard way with Proxmox API tokens
  and privilege separation).

## Current state

Check `docs/BACKLOG.md` for the authoritative list of what's done vs.
deferred. As of the last major session: Proxmox cluster + storage pools +
MinIO remote state backend are built and verified; Cloudflare DNS,
Entra ID App Registration, Backblaze B2 bucket, and Proxmox ACME have all
been retrofitted into OpenTofu management. The RKE2 VM provisioning
(`opentofu/modules/proxmox-vm`, `environments/prod`) has not been started
yet — that's the next major piece.