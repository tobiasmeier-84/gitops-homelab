# ADR-0054: Per-app backup with a hard maximum age (chart `app-backup`)

**Status:** Accepted - first user: forscher-app (2026-11-03)

## Context
forscher-app is built with privacy as a design concept: its own retention maximum is 14 days. A
backup must never keep personal data longer than that, even if that costs restorability. The existing
Nextcloud chart (`backup-cronjob`, ADR-0005/0006/0022) is tied to Nextcloud (maintenance mode,
PostgreSQL dump, 200 Gi stage volume, count-based retention) and its credentials reach whole buckets
and the whole vault.

## Decision
- New chart `gitops/charts/app-backup`, one ArgoCD Application per app (`gitops/apps/<app>-backup`).
  Needed per app: name, namespace, PVC, uid/gid of the files. Everything else has defaults.
- Same safety model as ADR-0005/0006: dual chain (OVH Chain A, Backblaze B2 Chain B), one age
  ciphertext with two recipients, keys stored in the vaults (Azure Key Vault, Bitwarden SM) and read
  back BEFORE any data is uploaded, chunked upload with size check, MANIFEST last.
- Consistency from a Longhorn VolumeSnapshot -> clone -> read-only worker pod. The app is not paused;
  SQLite WAL files are in the snapshot, so the restored database recovers as after a crash.
- **Retention is by age, not by count.** The age is read from the backup name
  `<app>-YYYYMMDD-HHMMSS` (UTC). Backups at `maxAgeDays` (13) or older are deleted from both chains
  together with their keys; incomplete leftovers older than a day too. Pruning runs at the START and
  at the END of every run and also after a failed run, so a broken backup job cannot extend the
  lifetime of personal data. Privacy overrides restorability: after 13 days without a successful
  run, nothing is left to restore.
- B2 gets a lifecycle rule as a second line (hide at 12 days, delete one day later). The OVH
  provider has no lifecycle setting (BACKLOG).
- **Dedicated credentials per app, scoped to the prefix `<app>-`:** OVH S3 user + policy, B2
  application key with `name_prefix`, own Azure Key Vault, own Bitwarden project and machine
  account. The `selftest` job proves the scoping (reads, writes and deletes outside the
  prefix are denied, the Nextcloud vault is closed, Bitwarden shows exactly one project).
- Exceptions, both accepted: the SMTP account is shared with the Nextcloud backup; the Bitwarden
  project and machine account are created by hand (the provider only manages secrets).
- The worker and orchestrator run under Pod Security `restricted`; a NetworkPolicy allows only
  public HTTPS/SMTPS and the Kubernetes API (the namespace has default-deny).

## Consequences
- The scripts duplicate the library of `backup-cronjob`. BACKLOG: one shared baseline for both.
- A failed mail or a broken job is the only alarm; success mails come once a week (Monday).
- Rollout: self-test job, then dry run (`dryRun: true`), then `dryRun: false`.
