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
