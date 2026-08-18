# ADR-0046: App-of-apps pattern, and the apps/ vs manifests/ directory split

**Status:** Accepted

## Context
As the number of ArgoCD-managed applications grows (cert-manager, Pella,
and more to come — Nextcloud, Harbor, monitoring), each one needs to be
onboarded into ArgoCD somehow. Doing this by hand for every app (`argocd
app create ...` via CLI, or clicking through the UI) doesn't scale and
directly conflicts with this project's core principle: everything should
be reconstructable from git alone, with no manual step required beyond
the very first cluster bootstrap.

## Decision

### Why app-of-apps at all
A single root `Application` (`gitops/bootstrap/root-app.yaml`, applied
once via Ansible during cluster bootstrap — see ADR-0040) watches one
directory (`gitops/apps/`) and recursively syncs whatever it finds
there. Every actual application is represented by its own small
`Application` manifest inside that directory. Adding a new app to the
cluster becomes: commit one new file, push, wait for ArgoCD's next sync
— no manual `kubectl`/`argocd` command ever needed again, for any app,
ever. This is also the mechanism that makes the future Crew tenant
self-service pattern (ADR-0042) possible: a tenant with permission to
add one file under `gitops/apps/` can onboard their own application
without anyone touching anything else.

### The apps/ vs manifests/ split
`gitops/apps/` contains **only** `Application` pointer objects — never
an app's real resources (Namespace, ConfigMap, CronJob, Deployment,
etc.) directly. Those live in a parallel, structurally separate
directory, `gitops/manifests/<app-name>/`, which the root Application
never scans:

gitops/
apps/
pella/application.yaml # picked up by the root's recursive scan
manifests/
pella/ # NOT scanned by the root at all
namespace.yaml
configmap.yaml
cronjob.yaml


`gitops/apps/pella/application.yaml`'s own `source.path` points at
`gitops/manifests/pella` — a second, independent `Application` that
owns those real resources once ArgoCD creates it from the pointer file.

## Reasoning

**Why this split matters, specifically:** the root Application is
configured with `directory: { recurse: true }`, meaning it recursively
applies *any* valid Kubernetes manifest found anywhere under
`gitops/apps/` — not just `Application` objects. If an app's real
resources (Namespace, CronJob, etc.) were placed directly under
`gitops/apps/<name>/` alongside its `application.yaml`, **two separate
ArgoCD Applications would end up believing they both own the same
resources** — the root (via its recursive scan) and the app's own
Application (via its `source.path`). ArgoCD tracks resource ownership
per-Application via annotations; two Applications claiming the same
resource causes sync-status flapping and field-ownership conflicts.
This is the same class of dual-controller problem deliberately avoided
earlier when Longhorn was kept under RKE2's own `HelmChart` management
rather than risking a clash with ArgoCD.

**Why not just avoid `recurse: true`?** A flat, non-recursive scan would
require every single app's manifests to live at the top level of
`gitops/apps/` with no subdirectory structure at all — much harder to
organize and browse as the number of apps grows. Recursive scanning
plus the two-directory split gets the organizational benefit without
the ownership conflict.

## Consequences
- **Rule going forward, for every future app:** its `Application`
  pointer file goes in `gitops/apps/<name>/application.yaml`; its real
  resources go in `gitops/manifests/<name>/`. Never place real
  resources directly under `gitops/apps/`.
- `gitops/apps/` is effectively a live, browsable index of "every
  application this cluster manages" — anyone can look at that one
  directory and know the complete list, without querying the cluster.
- Discovered and fixed during Pella's implementation — this ADR exists
  specifically because the pattern was designed live in conversation
  and never written down until a follow-up question surfaced the gap.