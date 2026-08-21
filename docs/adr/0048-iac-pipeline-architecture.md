# ADR-0048: Self-hosted CI/CD pipeline for OpenTofu and Ansible changes

**Status:** Proposed — architecture agreed, not yet built

## Context
Every OpenTofu and Ansible change in this project has, until now, been
applied manually from the operator's own Mac — requiring direct SSH
access to every VM and, for Proxmox work, direct access to port 8006.
This is in tension with the ZTNA goal (ADR-0045/0047): the operator
still needs standing direct access purely to *run infrastructure
changes*, separate from the narrower exception already accepted for
OpenTofu's own API-token workflow. It also means infrastructure changes
have no automatic validation step (a `tofu plan`/`ansible --check`)
before a real `apply` — unlike the application layer, where ArgoCD
already validates and applies every change automatically from git.

## Decision

### A self-hosted GitHub Actions runner, in the MGMT segment
A dedicated VM (Uranus-tier naming per ADR-0044 — **Umbriel** proposed,
adjustable) runs a self-hosted GitHub Actions runner. The runner polls
GitHub outbound; GitHub never needs inbound access to the homelab at
all — no new firewall hole required for the CI mechanism itself.

### Two-stage workflow, mirroring ArgoCD's own plan-then-apply discipline
- **On every push** to a branch touching `opentofu/` or `ansible/`:
  run `tofu plan` (per changed directory) and `ansible-playbook --check
  --diff`. Read-only, safe to run fully automatically.
- **On a git tag** (e.g. `v1.2.3`): run the real `tofu apply` /
  `ansible-playbook` for the corresponding change. This is the step
  that actually touches live infrastructure.

### A required approval gate before `apply`, even after tagging
Using GitHub Actions "environments" with required reviewers — pushing
a tag triggers the workflow, but the actual `apply` step pauses for one
manual approval click before running. `plan`/`check` needs no such gate
(read-only); `apply` genuinely changing live infrastructure does.

### A dedicated SOPS age key for the runner, not a copy of the operator's own
SOPS supports multiple recipients per encrypted file — both the
runner's key and the operator's personal key can independently decrypt
the same secrets. If the runner (a genuinely higher-value target, given
it needs standing access to essentially every credential in
`homelab-env.sh`) is ever compromised, only its key needs revoking and
rotating, not the operator's own.

## Reasoning

**Why self-hosted over a hosted CI service:** every secret this
pipeline needs (Proxmox API token, VM SSH keys, SOPS age key, Entra ID
app credentials) would otherwise need to leave the homelab entirely to
reach a third-party-hosted runner — in direct tension with the
self-hosting principle that's driven nearly every tool choice in this
project (Pomerium Core over Zero, CoreDNS over a hosted DNS filter,
etc.).

**Why a runner, not a webhook-triggered script:** GitHub's own runner
model already solves polling, job queuing, log capture, and the
environment-approval-gate mechanism — reimplementing that from scratch
would be substantial, low-value effort given a well-supported existing
tool.

**Why the security posture (dedicated key, approval gate) is treated as
non-negotiable, not an later optimization:** this pipeline, once built,
has the broadest standing credential access of anything in the entire
project — broader than any single VM's own role-scoped secrets. Adding
these controls after the fact, once the pipeline is already relied on
daily, would be considerably harder than designing them in from the
start.

## Consequences
- Once built, the operator's own workstation should need direct
  SSH/8006 access **only for genuine troubleshooting**, not routine
  changes — routine infrastructure changes become git-driven, matching
  the application layer's existing GitOps discipline.
- Scope not yet finalized: exact list of secrets the runner needs,
  whether `ansible --check` genuinely covers enough real risk to be
  trusted as "safe to auto-run" for every role (some Ansible tasks are
  not perfectly idempotent-safe to merely "check" — worth auditing
  before rollout, not assuming).
- This is a substantial enough piece of new infrastructure to deserve
  its own dedicated build session, not something to rush after an
  already-long session.