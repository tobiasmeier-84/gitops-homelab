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

## Addendum: trusted_domains index confusion

An initial manual fix (`trusted_domains 0 --value=rocinante.gate.solsys.dev`,
`trusted_domains 1 --value=nextcloud.app.solsys.dev`) silently overwrote
index 0's existing `localhost` entry rather than appending — `localhost`
is needed internally (health probes, CLI) and its removal caused
Nextcloud's own trusted-domain check to reject all traffic, including
`kube-probe` health checks, resulting in a sustained `CrashLoopBackOff`
that went unnoticed for roughly 15 hours (spanning a work break). The
same incorrect two-index assumption was carried into the OIDC
post-sync Job's own script, meaning every future sync would have
reintroduced the same failure. Root cause diagnosed by mounting the
Nextcloud PVC read-only into a stable debug pod (bypassing the crash
loop entirely) and reading `config.php` directly — confirmed `localhost`
was missing from the trusted domains array. Fixed by always setting
all three indices explicitly, with `localhost` fixed at index 0.

## Addendum: OIDC configured, login confirmed working

Following the earlier decision to scope OIDC to authentication only
(not automatic admin-group provisioning, given confirmed real-world
reliability issues with `user_oidc`'s group provisioning against
Nextcloud's built-in `admin` group), the ArgoCD post-sync Job
(`gitops/apps/rocinante-oidc/`) successfully configured the `entraid`
OIDC provider. End-to-end login via Entra ID confirmed working. Admin
rights for the Captain-tier operator were granted manually via a
one-time `occ group:adduser admin <username>` command, consistent with
the deliberately smaller, more reliable scope chosen over automatic
provisioning.

## Addendum: OIDC configured, login confirmed working

Following the earlier decision to scope OIDC to authentication only
(not automatic admin-group provisioning, given confirmed real-world
reliability issues with `user_oidc`'s group provisioning against
Nextcloud's built-in `admin` group), the ArgoCD post-sync Job
(`gitops/apps/rocinante-oidc/`) successfully configured the `entraid`
OIDC provider. End-to-end login via Entra ID confirmed working.

**Granting admin rights is a deliberate manual step, not automated:**
```bash
POD=$(kubectl get pod -n rocinante -l app.kubernetes.io/name=nextcloud -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n rocinante $POD -- su -s /bin/sh www-data -c 'php occ group:adduser admin <username>'
```
Consistent with the deliberately smaller, more reliable scope chosen
over automatic provisioning — a one-time action for a single-operator
home lab, not worth automating given the confirmed unreliability of
the alternative.

## Addendum: --unique-uid=0 required alongside --mapping-uid

Setting `--mapping-uid=preferred_username` alone was **not** sufficient
to get a readable username — `user_oidc` has a separate `uniqueUid`
setting (default `true`) that silently takes precedence, generating an
opaque SHA-256-style hash as the actual account ID regardless of the
UID mapping claim. The display name and email correctly reflected the
mapped claims the whole time, masking the fact that the underlying
`user_id` was still the wrong value — only visible via `occ
user_oidc:provider entraid`'s own JSON output, not from the login flow
itself. Confirmed the hard way: two full login attempts, plus a pod
restart to rule out config caching, before finding the actual second
flag. Fixed by adding `--unique-uid=0` alongside `--mapping-uid`.

## Addendum: the chart's own bootstrap admin account is a legitimate break-glass path

While troubleshooting, discovered the Nextcloud Helm chart auto-creates
a local `admin` account with a randomly generated password on first
install (retrievable via the `rocinante-nextcloud` Secret's
`nextcloud-password` key) — independent of OIDC/Entra ID entirely.
Rather than treat this as an oversight to remove, it's being kept
deliberately as a genuine break-glass login path — consistent with the
same philosophy behind Deimos/Titania/Oberon's direct-SSH exception
(ADR-0047): if Pomerium, Entra ID, or the OIDC provider config ever has
trouble, this local account provides a way in that doesn't depend on
the systems being troubleshot. The operator changed its password from
the auto-generated default upon discovery.