# ADR-0036: OpenTofu state bucket backup — simple, single-copy

**Status:** Accepted

## Context
`iapetus` (the self-hosted MinIO instance providing OpenTofu's remote state backend, ADR-0024) runs as a single VM on `ceres`. Total loss of all 3 Proxmox nodes destroys `iapetus` and every state file it holds. Since the underlying infrastructure those state files describe is also destroyed in that scenario, a fresh `tofu apply` from the committed `.tf` configs already provides a recovery path without needing the old state at all — but restoring actual state (rather than reapplying from scratch) is a meaningfully faster and lower-risk recovery option worth having.

A separate, related discovery while designing this: OpenTofu/Terraform state files can contain secrets in plaintext (the `sensitive = true` variable flag only hides values from CLI output, not from the state file itself) — e.g. `bootstrap-minio`'s state very likely contains the MinIO root password unencrypted.

## Decision
Back up the OpenTofu state bucket with a **simple, single-copy** backup (one provider, one static encryption key) — not the full dual-chain, per-run-rotating-key design used for application data (ADR-0005). Runs via a systemd timer directly on `iapetus` (not a Kubernetes CronJob, since no cluster exists at this stage of the build).

**Confidentiality and availability are treated as separate problems with separate solutions**: the plaintext-secrets-in-state issue is properly addressed by enabling OpenTofu's own native state encryption feature (one of ADR-0010's original reasons for choosing OpenTofu over Terraform) — logged here as a backlog item, not solved by this backup. Once state encryption is enabled at the source, this backup only needs to provide durability, not confidentiality, which is why a single-copy design is sufficient rather than needing ADR-0005's full cross-provider blast-radius protection.

## Reasoning
- State-file loss in a *total* infrastructure loss scenario is recoverable via "reapply from git" alone — this backup exists to make that recovery faster and lower-risk, not because the alternative is unrecoverable.
- Solving "secrets in state" via an elaborate backup scheme would be treating the symptom, not the cause — native state encryption is the correctly-scoped fix.
- Matching ADR-0005's full complexity here would be disproportionate to what's actually at stake for this specific artifact.

## Consequences
- **Backlog item**: enable OpenTofu native state encryption across all configs using the MinIO backend (`bootstrap-storage`, and future `environments/prod`) — this is the correct fix for plaintext secrets in state, not yet implemented.
- If `iapetus` itself is compromised (not just lost), the single backup copy and its single key together are enough to reconstruct state contents — an accepted, smaller blast radius than ADR-0005's app-data design, justified by the lower stakes of this specific artifact.
- Retention is time-bounded (see implementation) to avoid unbounded storage growth, given backups run frequently but each one is small.