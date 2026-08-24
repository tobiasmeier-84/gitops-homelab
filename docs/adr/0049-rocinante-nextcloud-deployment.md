# ADR-0049: Rocinante (Nextcloud) — first application-tier deployment

**Status:** Accepted

## Context
With ArgoCD, cert-manager, Longhorn (bulk/fast tiers), and the ZTNA
architecture all in place, Nextcloud became the first genuine
application-tier workload — proving the platform's app-of-apps pattern
(ADR-0046) end to end with a real, live service rather than
infrastructure. Named `Rocinante`, the established flagship ship.

## Decision

### Database: CloudNativePG, not the chart's suggested Bitnami option
The official Nextcloud Helm chart's own README still points to Bitnami's
prepackaged PostgreSQL subchart. Verified before building: Bitnami's
free public chart catalog was largely discontinued as of September
2025 (moved behind a paid "Bitnami Secure Images" subscription, with
only an unpatched "legacy" repo remaining). Used **CloudNativePG**
instead — a CNCF-recognized, purpose-built Kubernetes operator for
PostgreSQL specifically, actively maintained, genuinely free. Matches
this project's consistent preference for purpose-built tools over
generic wrappers (Longhorn, Canal, CoreDNS).

### Database workload named separately: Barbapiccola
Following the established "workloads = ships" convention, with the
added refinement that the database — Belter faction, since Belter
ships haul cargo, an apt parallel for a component whose whole job is
carrying another workload's actual data. Single instance (not 3-way
HA), matching the project's established "no HA where downtime is
recoverable and modest" pattern (same reasoning as Deimos).

### Storage tiers used as originally designed
`tachi` (fast tier) for Barbapiccola's database — the exact use case
this tier was created for, early in the project, finally realized.
`canterbury` (bulk tier) for Nextcloud's actual file storage (150Gi).
`Retain` reclaim policy on both, consistent with every other Longhorn
StorageClass in this project.

### PSA exemption extended to `rocinante`
The official Nextcloud Docker image (Apache-based) has a confirmed,
long-standing limitation (multiple open GitHub issues against
`nextcloud/docker`, some dating back years): it cannot run fully
non-root — needs root to bind port 80, create PID files, and fix
filesystem permissions at container startup. Rather than weaken the
cluster-wide `restricted` PodSecurity policy, `rocinante` was added to
the same namespace exemption list already established for
`longhorn-system` (ADR-0041) — the second confirmed real-world case of
this pattern, not a new mechanism.

## Real mistakes made and caught during this build

1. **Guessed Helm chart version (`6.6.11`) didn't exist** — current
   stable was actually `9.1.1`. Verified via search before retrying
   rather than guessing a second time.
2. **`externalDatabase.enabled` was never set to `true`** in the first
   draft — a genuinely silent failure mode, since the chart would have
   quietly fallen back to its own internal SQLite rather than erroring
   outright. Caught only by deliberately re-verifying the chart's real
   `values.yaml` against the draft before applying, not by any error
   message.
3. **`storageClassName` vs. `storageClass`** on CloudNativePG's own
   `Cluster` CRD — the wrong field name was silently ignored (no error),
   letting the database land on Longhorn's *default* class
   (`longhorn-bulk`) instead of the intended `longhorn-fast`. Caught by
   deliberately checking the live PVC's actual storage class after
   creation rather than trusting the applied manifest — confirmed via
   `kubectl explain cluster.spec.storage`, the authoritative source,
   rather than continuing to guess. Fixed by deleting and recreating
   the (still-empty, newly-created) database cleanly.
4. **CloudNativePG's CRDs exceeded Kubernetes' 256KiB annotation limit**
   under ArgoCD's default client-side apply — fixed with
   `syncOptions: ServerSideApply=true`, the standard, documented
   pattern for this class of issue (large-schema CRDs), not specific
   to CloudNativePG.
5. **Nextcloud reported itself as `http://`, not `https://`, in
   redirects** — didn't know it was being accessed over TLS, since
   Traefik terminates HTTPS and forwards plain HTTP internally. Fixed
   with `OVERWRITEPROTOCOL=https` via `nextcloud.extraEnv`.

## Consequences
- Real, live, first application-tier workload — genuine proof the
  whole platform (Longhorn, cert-manager, ArgoCD, app-of-apps, PSA
  exemption pattern) works together for something beyond infrastructure
  itself.
- SSO integration (Entra ID, Captain/Crew/Passenger extended to
  `rocinante-*`) not yet built — tracked as a follow-up, not part of
  this initial deployment.
- User's own account data migration from the existing
  `nextcloud.topadata.ch` instance is a deliberately separate, manual,
  user-driven process — not automated as part of this build.