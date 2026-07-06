# ADR-0004: Secrets management — SOPS + age

**Status:** Accepted

## Context
The repository is public. No secret material may ever be committed in plaintext.

## Decision
SOPS with an age keypair. The public key is committed to the repo (`.sops.yaml`); the private key is held only on the operator's workstation/password manager, never in git.

## Reasoning
Encrypted files remain structurally readable in diffs and PRs without exposing values. A pre-commit hook (`detect-secrets`) adds an automated guardrail against accidental plaintext commits, on top of SOPS encryption itself.

## Consequences
Loss of the private age key means loss of ability to decrypt existing secrets. This same tension — a key that must never be backed up alongside the thing it protects — reappears deliberately in the backup design (ADR-0005).
