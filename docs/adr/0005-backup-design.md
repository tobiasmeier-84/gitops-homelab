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