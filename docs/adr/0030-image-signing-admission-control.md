# ADR-0030: Image signing and admission control via cosign

**Status:** Accepted

## Context
Harbor's vulnerability scanning (ADR-0017) checks images for known CVEs but doesn't verify that a running image actually originated from this repo's own CI pipeline, as opposed to a tampered or substituted image.

## Decision
Sign images with cosign as part of the CI build pipeline (the same pipeline that builds and pushes the backup CronJob image and any other custom images), and enforce signature verification via a Kubernetes admission policy (e.g. Kyverno or the sigstore policy-controller) that rejects unsigned images at deploy time.

## Reasoning
Vulnerability scanning and provenance verification are different guarantees — this closes the "is this actually my image" gap that scanning alone doesn't address, extending the same supply-chain-conscious posture already applied to secrets and backups.

## Consequences
Every custom-built image must go through the signing step before it can be deployed; a new failure mode to handle in CI (a build that succeeds but fails to sign shouldn't silently deploy an unsigned image).