# ADR-0005: Backup design — dual-chain, cross-provider, per-run encryption

**Status:** Accepted

## Context
All configuration is already reconstructable from git (Terraform/Ansible/GitOps). Only application data (Longhorn-backed PVs) needs a dedicated backup strategy.

## Decision
Two independent backup chains. Each run: snapshot the PV via Longhorn, restore to a temporary PVC, compress (zstd), encrypt with a freshly generated per-run age key, upload the encrypted blob to that chain's cold-storage provider, and store that run's private key in a *different* provider than the one holding the data it decrypts.

- **Chain A:** data → Backblaze B2, key → Azure Key Vault
- **Chain B:** data → Hetzner Storage Box / Wasabi, key → Bitwarden Secrets Manager

## Reasoning
A single compromised or unavailable provider can never expose both a backup and its key. Using two full independent chains (not just two providers for one chain) means the two copies are organizationally, not just geographically, independent.

## Consequences
A non-secret manifest (`backups/manifest.jsonl`, committed to git) tracks which key/provider pair decrypts which backup file, since every run generates a new key. Ephemeral per-run private keys are the one artifact in this platform deliberately never stored in git.

## Addendum: Provider selection revised — genuine archive-tier pricing and jurisdictional diversity

**Status of this addendum:** Supersedes the original Chain A/B provider choices
(Backblaze B2 / Azure Key Vault, Hetzner-or-Wasabi / Bitwarden Secrets
Manager). The core security property — no single company ever holds
both a chain's data and its matching key — is unchanged and remains
the governing design constraint.

### Why the original providers were reconsidered

Two separate concerns surfaced once real Nextcloud data (~140GB) made
this decision concrete rather than theoretical:

1. **Cost model mismatch.** Backblaze B2 and Wasabi are "cheap flat-rate
   hot storage" — inexpensive per GB, but priced to be accessed
   regularly. The actual requirement is the opposite: pay almost
   nothing at rest, pay only when a genuine recovery happens. That's a
   fundamentally different pricing shape — true archive/cold-storage
   tiers (AWS Glacier Deep Archive, Azure Archive, genuine EU/Asian
   equivalents), not discounted hot storage.

2. **Jurisdictional exposure.** The original design's "different
   company" requirement doesn't actually protect against the **US
   CLOUD Act**, which compels any US-domiciled company to disclose
   data regardless of physical server location — meaning AWS, Azure,
   Google, Backblaze, Wasabi, and Bitwarden are *all* reachable under
   the same legal framework, even split across "different" providers.
   Genuine protection requires the *company's legal domicile*, not
   just its brand, to differ — and ideally the two legs of a chain sit
   in jurisdictions unlikely to cooperate with each other at all.

### Decision: four countries, two chains, no change to the core security property

- **Chain A**: data → **Scaleway Glacier** (Scaleway SAS / Iliad Group,
  France) — no minimum storage duration, ~€0.002/GB/month, first 75GB
  free. Key → a Swiss provider (Infomaniak or Exoscale) — outside both
  EU and US jurisdiction, strong data-sovereignty posture.
- **Chain B**: data → **Alibaba Cloud OSS Deep Cold Archive** (Singapore
  region) — China-domiciled, ~$0.001-0.0015/GB/month. Key → **Azure
  Key Vault** (or Google Secret Manager) — US-domiciled.

Rationale for the specific pairing: France↔Switzerland and China↔US
are each pairs of jurisdictions with no meaningful legal-compulsion
cooperation — a single government (or even a single treaty
arrangement) cannot compel both halves of either chain. The China↔US
split for Chain B is deliberately adversarial: these two governments
will not jointly cooperate to compel data disclosure, making that
tension a genuine security asset rather than a risk.

### Real pricing findings, incorporated into retention planning

- **AWS, Azure, Alibaba all impose a 180-day minimum storage duration**
  — deleting/pruning an object before 180 days still bills the full
  180 days. Google's Archive tier is worse, at 365 days. **OVHcloud
  Cold Archive was evaluated and rejected** specifically because its
  1TB-per-bucket minimum billing floor makes it ~7× overpriced at our
  actual 140GB scale.
- **Scaleway Glacier has no minimum storage duration** — the deciding
  factor in choosing it as the primary EU data leg, since it tolerates
  off-schedule pruning without penalty.
- **AWS Secrets Manager was evaluated and rejected for the key leg**:
  it charges a flat $0.40/secret/month regardless of size or access
  frequency. Since this design generates a brand-new key on every
  backup run, this would scale to real, escalating monthly cost (~$12+/month
  for a month of daily-backup keys) — directly defeating the "pay
  almost nothing at rest" goal. Azure Key Vault's operation-based
  pricing (~$0.03/10,000 operations, no per-secret storage fee) is
  the correct fit for this specific "many small, frequently-rotated
  secrets" access pattern.
- **Retention policy set accordingly**: weekly full backups, GFS
  pruning (~4 weekly + ~6 monthly ≈ 10 live copies per chain), every
  object retained ≥180 days — avoiding early-deletion penalties
  entirely on the Alibaba leg, while Scaleway's no-minimum policy
  absorbs any exceptions.
- **Realistic combined at-rest cost at steady-state (~1.4TB/chain):
  ~$5-10/month total**, both key legs effectively free. One full
  annual test-restore: a few euros from the Scaleway chain, roughly
  $10-20+ from the Alibaba chain (egress dominates recovery cost, not
  the archive retrieval fee itself).

### Known trade-offs, accepted deliberately

- Alibaba Cloud's international-region archive pricing couldn't be
  fully verified from a quotable public source (JavaScript-rendered
  pricing page) — figures are estimates anchored to confirmed mainland
  pricing and confirmed restore-replica rates; worth re-confirming
  with a live quote before final commitment.
- Alibaba's KYC/account-setup process is the heaviest of any candidate
  provider (ID verification, card pre-authorization, overseas phone
  number, ~3 business day review) — budget real setup time.
- Scaleway has a documented 2021 public incident involving permanent
  data loss on Glacier with limited compensation/support response —
  this is exactly why it's never the *only* copy of anything in this
  design, only ever one leg of a dual-chain system.
- Full findings, comparison tables, and alternative architectures
  considered (including an all-EU fallback and pure-AWS options) are
  preserved in the full research report for reference.

### Consequences
- Hetzner Storage Box, Wasabi, and Bitwarden Secrets Manager are no
  longer part of the backup architecture — genuinely reasonable tools,
  just not the right fit for this specific cost model and threat model.
- `backups/manifest.jsonl`'s existing design (tracking which key/provider
  pair decrypts which backup file, since every run generates a new
  key) is unchanged — this addendum only changes *which* providers
  fill each of the four roles (2 chains × data/key), not the
  underlying mechanism.
- Real account setup work is now needed across 4 genuinely new
  providers (Scaleway, a Swiss provider, Alibaba Cloud, and reusing
  the existing Azure tenant for the 4th role) before this design can
  actually be implemented.

## Addendum: archive-tier storage abandoned in favor of "hot" storage with no minimum duration

**Status of this addendum:** Supersedes the earlier "four countries, archive-tier"
revision. The core security property — no single company ever holds
both a chain's data and its key — remains unchanged.

### Why archive tiers were abandoned

Real, verified pricing research found that every true archive/cold-storage
tier (AWS Glacier Deep Archive, Azure Archive, OVHcloud Cold Archive,
Scaleway Glacier, Alibaba Deep Cold Archive) imposes a **minimum storage
duration before an object becomes eligible for cheap pricing, and/or a
minimum storage duration once archived** (Scaleway: 90 days before
transition; OVHcloud: 30 days before transition + 180 days once archived;
AWS/Alibaba: 180 days; Google: 365 days). These penalties are specifically
designed around infrequent-access-but-long-lived data — they interact
badly with a genuinely small-scale (~140GB), infrequently-recovered
(once-per-decade) personal backup, where the "savings" from cheap
archive-tier per-GB pricing are outweighed by paying full-price Standard
tier rates during the mandatory pre-transition window, especially under
any reasonable retention/rotation schedule.

### The correct fit for this specific use case: "hot" storage with zero minimum duration

**Cloudflare R2** ($0.015/GB/month, confirmed zero egress fees at any
volume, no minimum duration, negligible per-request operation costs) and
**Backblaze B2** ($6.95/TB/month, confirmed no minimum storage duration —
*"you can delete data at any time without penalty"* — free egress up to
3× average monthly storage) both eliminate the exact penalty structure
that made archive tiers a poor fit at this scale. Verified: ingress
(upload) is free on both providers, and industry-wide — OVHcloud's
"Cloud Archive" per-GB ingress fee (a different product from "Cold
Archive," confirmed as a real source of earlier confusion) is a genuine
outlier, not the norm.

### Final design

- **Chain A**: data → Cloudflare R2, key → Azure Key Vault
- **Chain B**: data → Backblaze B2, key → Bitwarden Secrets Manager
- **Retention**: 2 live copies per chain, replaced on each run — safe
  and cost-free given neither provider penalizes early deletion, unlike
  every archive-tier option evaluated.
- **Real, verified annual cost**: ~$75/year combined (R2: ~$50/year,
  B2: ~$23/year, key storage: negligible, test-restores: effectively
  free given both providers' generous/zero egress terms) — comfortably
  under the ~$90-100/year target.

### Jurisdictional diversity: explicitly and deliberately abandoned

Cloudflare, Backblaze, Microsoft (Azure Key Vault), and Bitwarden Inc.
are all US-domiciled companies — every leg of this design sits under
the same legal framework (US CLOUD Act). This was a deliberate,
informed trade-off: cost was explicitly prioritized over jurisdictional
diversity once real numbers showed the four-country design would have
cost meaningfully more, and the operator confirmed this trade-off
directly after being shown the real cost-vs-jurisdiction choice. The
data≠key separation still protects against a single company's internal
breach or insider threat — just not against coordinated US
government legal compulsion across all four providers simultaneously,
which was the original, now-deprioritized concern.

### Lesson worth keeping in mind for any future storage decision

Archive/cold-storage tiers are not automatically the cost-optimal
choice — their entire pricing model is built around a specific access
pattern (large volumes, genuinely rare access, long retention) that
doesn't automatically apply just because "recovery is rare." At small
scale with flexible retention, a well-chosen "hot" tier with no
minimum-duration penalty and low/zero egress can be meaningfully
cheaper. Worth genuinely comparing both, as was done here, rather than
assuming "archive tier = cheaper" by default.

## Addendum: final provider selection — cost-optimal AND partial jurisdictional diversity

**Status of this addendum:** Supersedes the "all-US" revision immediately
prior. The core security property is unchanged.

### One more verification pass, at the operator's request

Before finalizing an all-US design, a final check specifically asked:
is there a genuinely cost-competitive EU or Chinese alternative when
ingress, storage, AND egress are all properly accounted for together?

**Finding: yes.** OVHcloud's plain **Standard Object Storage** tier
(not "Cold Archive," not "Cloud Archive" — the ordinary, no-strings
tier) was confirmed, from OVHcloud's own official pricing table:
**$0.0081/GB/month storage, free ingress AND egress, no minimum
storage duration.** This is genuinely cheaper than Cloudflare R2
($0.015/GB) — not a tradeoff between cost and jurisdiction, an
improvement on both simultaneously, since OVH SAS is a French company.

No equally strong Chinese alternative was found — Alibaba's confirmed
pricing includes real, non-trivial egress fees, unlike the free/near-
free egress on OVHcloud Standard, R2, and B2, making it a worse fit
for actual restore cost despite cheap storage.

### Final design

- **Chain A**: data → OVHcloud Standard Object Storage (Paris),
  key → Azure Key Vault
- **Chain B**: data → Backblaze B2, key → Bitwarden Secrets Manager
- **Retention**: 2 live copies per chain, replaced on each backup run
- **Real, verified annual cost**: ~$50-52/year combined — below every
  prior estimate, while also restoring genuine jurisdictional
  diversity on one full chain (France vs. the remaining three US-
  domiciled legs), at zero cost premium.

### Lesson worth keeping for future provider decisions

The "cost vs. jurisdiction" tradeoff assumed earlier in this whole
process turned out to be partially false — assuming a non-US option
must cost more is itself an unverified assumption, and it was wrong
here. Worth checking real numbers before accepting a tradeoff as given,
even after a design otherwise feels finalized.

## Addendum: OVHcloud Chain A data leg provisioned — two real gotchas found

**Status:** Scopuli (Chain A's OVHcloud data bucket) fully provisioned
via OpenTofu, confirmed working end-to-end (real PutObject/ListBucket
tested via the AWS CLI against the actual S3-compatible endpoint).

### Gotcha 1: OVHcloud's Object Storage region name is case-sensitive

The API rejected `region_name = "eu-west-par"` with `"Invalid region
parameter"`, despite this being the exact string OVHcloud's own public
documentation uses. The actual required value, confirmed directly from
the OVHcloud control panel's own bucket-creation dropdown, is
**`EU-WEST-PAR`** (uppercase). Lowercase — genuinely identical in every
other respect — is silently rejected as invalid rather than
normalized. Worth checking the console's exact displayed string
directly for any future OVHcloud region-scoped resource, rather than
trusting documentation casing.

### Gotcha 2: `role_names` alone does not grant S3 data-plane access — a separate policy resource is required

Creating a user with `role_names = ["objectstore_operator"]` and
generating S3 credentials both succeeded, and the credentials were
valid (non-empty, correctly formatted) — but every actual S3 operation
(`PutObject`, `ListObjectsV2`) returned `AccessDenied`. Root cause,
confirmed against two independent sources (OVHcloud's own Pulumi
provider examples, which share the identical underlying API as the
Terraform/OpenTofu provider, and a real working community Terraform
module for OVH S3): **`role_names` grants project-level management
rights** (create/delete buckets via OVHcloud's own control-plane API)
**but not S3-protocol data access** — these are two genuinely separate
permission layers. A dedicated `ovh_cloud_project_user_s3_policy`
resource, with an explicit AWS-IAM-style policy document scoped to the
specific bucket ARN, is required for actual read/write object
operations:

```hcl
resource "ovh_cloud_project_user_s3_policy" "backup_writer" {
  service_name = var.ovh_project_id
  user_id      = ovh_cloud_project_user.backup_writer.id
  policy = jsonencode({
    Statement = [{
      Sid    = "RWContainer"
      Effect = "Allow"
      Action = [
        "s3:GetObject", "s3:PutObject", "s3:DeleteObject",
        "s3:ListBucket", "s3:ListMultipartUploadParts",
        "s3:ListBucketMultipartUploads", "s3:AbortMultipartUpload",
        "s3:GetBucketLocation",
      ]
      Resource = [
        "arn:aws:s3:::scopuli-chain-a-backup",
        "arn:aws:s3:::scopuli-chain-a-backup/*",
      ]
    }]
  })
}
```

Also worth noting: after this policy resource applied successfully
(confirmed via `tofu state show`), the very first S3 operation still
failed with `AccessDenied` — resolved after waiting roughly 60 seconds
and retrying, consistent with genuine IAM propagation delay rather
than a configuration error. Worth expecting this delay on any future
OVHcloud IAM/policy change, not treating an immediate post-apply
failure as proof the config itself is wrong.

### Consequences
- `opentofu/backup-infra-ovhcloud/` now fully provisions Scopuli,
  confirmed working.
- Chain A (Scopuli data + Azure Key Vault key) is now fully
  provisioned on both legs.
- Chain B (Backblaze B2 data + Bitwarden Secrets Manager key) remains
  to be built.


## Addendum: backup worker implementation, real scaling limit found and fixed

**Status:** The full dual-chain backup pipeline (snapshot → restore →
compress → dual-encrypt → dual-upload → dual-key-storage → retention
pruning) is implemented and verified working end-to-end, including
real data uploads to both OVHcloud and Backblaze, real key storage in
both Azure Key Vault and Bitwarden, and real pruning of both data
blobs and their matching keys.

### The real scaling ceiling, found through actual testing — not the one originally assumed

Early testing revealed the binding constraint wasn't Longhorn's
`canterbury` storage pool (hundreds of GB free) — it was the RKE2
nodes' own **OS root disk**, originally provisioned at just 40GB per
node. The worker pod's compression step wrote its intermediate
archive to node-local `/tmp`, and with real data (~150GB+), this
exhausted the root disk's genuine free space, causing Kubernetes to
evict the pod outright (`low on resource: ephemeral-storage`) — a
failure mode that looked like a stuck/hung pipeline in earlier testing
but was actually a hard resource ceiling.

### Two-part fix: bigger root disks now, dedicated scratch storage for the real long-term fix

1. **Immediate relief**: grown all three RKE2 nodes' root disk from
   40GB to 300GB (live, in-place resize via OpenTofu + `growpart` +
   `resize2fs`, no downtime — confirmed via `pvesm status` that the
   underlying `razorback` ZFS pool had genuine headroom, ~380GB free
   at the time, with a deliberate 20% reserve maintained).
2. **The real, permanent fix**: the worker pod no longer uses node-local
   disk for scratch space at all. A dedicated, disposable PVC
   (`longhorn-bulk-single-replica` class, same proven class used for
   the restore volume) is created and destroyed alongside every backup
   run, mounted at `/scratch`. This decouples the maximum backup size
   from the node's own boot disk entirely — the real ceiling is now
   `canterbury`'s pool capacity (hundreds of GB free per node,
   independently resizable later without ever touching a node's OS
   disk again).

### Also fixed in the same implementation pass: streaming encryption, eliminating a second storage multiplier

The original design wrote the compressed archive, then wrote two full
*separate* encrypted copies (one per chain) before uploading — meaning
peak local storage usage was roughly 3x the compressed archive's size.
The corrected worker script pipes `age`'s encryption output directly
into the upload command (`age ... | aws s3 cp -`), so no encrypted
blob ever touches disk at all. Combined with the scratch-PVC move,
peak storage usage during a backup run is now just the compressed
archive's own size — the real, permanent floor.

### Retention and pruning, implemented as designed

Confirmed working: after each successful upload, the worker lists
existing backups per chain, keeps the 2 most recent, and deletes
anything older — both the data blob *and* its matching key in the
corresponding vault (Azure Key Vault secret delete+purge; Bitwarden
secret delete by matching key name). Pruning only runs after a
genuinely complete, successful new backup — `set -e` guarantees any
earlier failure (compression, either upload, either key-storage step)
exits before pruning code is ever reached, so old backups can never be
deleted without a verified-successful replacement already in place.

### Hard-won lessons from this implementation, worth remembering for any future non-root Alpine worker container

- **Never trust a base image's pre-installed tools** — `alpine/k8s`
  claiming to include `aws`/`curl`/`jq` proved unreliable in practice
  (confirmed present in isolated test pods, then genuinely absent in
  the real worker pod using the identical image tag and security
  context — cause never fully explained). The reliable fix: self-install
  every tool explicitly via `apk add --root /tmp/pkgroot`, never
  assume anything is already there.
- **`apk --root --initdb` needs `--repositories-file` and
  `--allow-untrusted`** — a fresh alternate root has no repository
  list and no trusted signing keys by default; omit either and package
  resolution/installation fails outright.
- **Post-install trigger scripts (busybox, ca-certificates) fail
  under non-root** (`chroot: Operation not permitted`) — genuinely
  harmless given none of their output is relied on (we call every tool
  via absolute path, never depend on busybox's symlinks or the
  consolidated CA bundle) — don't let `set -e` treat this as fatal.
- **A binary with an embedded shebang path** (`aws`'s
  `#!/usr/bin/python3`) **will fail if that exact absolute path
  doesn't exist in the container**, even though the file itself is
  present and executable — invoke the real interpreter explicitly
  rather than rely on the shebang.
- **Never combine a binary path and a flag into one shell variable**
  or quote them together — `CURL="/path/curl -k"` invoked as `"$CURL"`
  makes the shell search for one literal, non-existent command; keep
  the flag in a separate variable, invoked unquoted.
- **`fsGroup` alone does not guarantee read access** — a directory
  with no group-read bit at all (Nextcloud's own `data/` folder,
  `drwxrws---`) genuinely requires running as the actual owning UID,
  not just adding group membership.
- **GitHub release asset filenames often embed the version number
  explicitly** — a "latest, no version" URL guess can silently 404,
  and `curl` will happily "succeed" downloading that error page as if
  it were the real file.
- **`kubectl logs` output is not a safe place for secrets** —
  suppress API response bodies (`-o /dev/null -w "...%{http_code}\n"`)
  for any call that echoes back the sensitive value it was just sent.

### Remaining, deliberately deferred
- Manifest/audit-trail recording (git-committed log of which blob
  pairs with which key) — decided unnecessary given only 2 backups
  ever exist per chain at once, trivially distinguished by embedded
  timestamp.
- Applying this same reusable `backup-cronjob` chart to additional
  apps beyond Rocinante.

## Addendum: real memory exhaustion incident during heavy backup testing, root cause and fix

**Status:** A genuine production incident occurred during extensive
same-day backup pipeline testing — root cause identified, confirmed
resolved, real fix applied. No data loss occurred (verified via direct
PostgreSQL row-count check before and after recovery).

### What happened

After many dozens of rapid backup test cycles in a single session
(each spinning up and tearing down Longhorn snapshot/restore/scratch
volumes, plus a `zstd -T0` compression process), the `rhea` RKE2 node
reached **over 100% of its allocated 24GB RAM**. This triggered a
cascade: multiple dynamically-attached Longhorn PVC devices
(`sdd`/`sde`/`sdf`/`sdh` — the transient restore/scratch volumes from
repeated testing, not the live application volumes) began throwing
real ext4 I/O errors and remounting read-only, `longhorn-manager`'s
instance-manager pod on `rhea` was recreated, and this cascaded into a
cluster-wide pod restart event affecting live application pods
(Barbapiccola/PostgreSQL, Nextcloud, Collabora).

### Root cause, confirmed via direct investigation, not assumed

1. **Physical storage was completely healthy throughout** — `zpool
   status -v` on all three Proxmox hosts showed every pool `ONLINE`,
   `0 0 0` errors, `No known data errors`, both before and after the
   incident. The I/O errors were a symptom of memory pressure
   corrupting the guest's I/O buffer/cache state, not any actual disk
   or hardware fault.
2. **`zstd -T0` uses every available CPU thread**, each with its own
   compression window buffer — genuinely reasonable for a single run,
   but memory usage from many rapid, consecutive test runs (plus
   Longhorn's own per-volume engine/replica overhead) accumulated
   faster than anticipated on a 24GB node.

### Recovery

A clean reboot of `rhea` fully resolved the incident — memory usage
returned to normal (~2GB of 23GB) immediately after restart. Both
affected application pods (`barbapiccola-1`, `rocinante-nextcloud`)
self-healed via Kubernetes' normal restart/backoff mechanism within a
few minutes, no manual data recovery needed. Data integrity confirmed
via direct `SELECT COUNT(*)` against the live PostgreSQL database
(`31,666` rows in `oc_filecache`), identical before and after the
incident.

### Fix applied: cap zstd's thread count to bound peak memory usage

```bash
"$ZSTD" -T4 -o "$ARCHIVE"
```

Changed from `-T0` (unlimited threads) to `-T4` — still genuinely fast
for a background weekly job, while keeping peak memory usage
predictable and bounded regardless of how many backup runs happen in
quick succession (e.g., during testing/development).

### Also fixed: leftover PVCs from interrupted test runs

Several times during testing, PVCs from a previous, no-longer-running
worker pod were found still present, contributing to real storage
scheduling pressure and confusion during subsequent test runs. This
reinforces the importance of the orchestrator's own `trap cleanup
EXIT` logic — worth periodically auditing for leftover
`*-restore-*`/`*-scratch-*` PVCs if testing is interrupted or a job is
manually deleted before its own cleanup can run.

### Lesson for future testing

Repeated, rapid-fire manual test cycles (many runs within a single
hour) place meaningfully more cumulative load on a node than the
actual weekly production schedule ever will — genuinely useful for
finding real bugs (as today's session did, repeatedly), but worth
pacing deliberately during heavy debugging sessions, or testing
against a node with more RAM headroom, to avoid tripping the same
memory-exhaustion cascade again.