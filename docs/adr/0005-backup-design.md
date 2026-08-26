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