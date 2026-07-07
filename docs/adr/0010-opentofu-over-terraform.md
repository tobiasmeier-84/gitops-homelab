# ADR-0010: Infrastructure-as-Code tool — OpenTofu over Terraform

**Status:** Accepted

## Context
Terraform's license changed from MPL 2.0 to the Business Source License (BSL) v1.1 in August 2023, restricting use "in a competitive way" against HashiCorp's own products. HashiCorp was acquired by IBM in February 2025. OpenTofu, a fork of the last MPL-licensed Terraform release, is governed by the Linux Foundation under MPL 2.0.

## Decision
Use OpenTofu instead of Terraform for all infrastructure provisioning (Proxmox VMs).

## Reasoning
- This repo's use case (personal infrastructure, public portfolio project) falls within what the BSL permits — this decision is not a compliance necessity.
- OpenTofu has shipped native state encryption (since v1.7), a feature Terraform's open-source CLI has never delivered. Terraform state routinely contains secrets in plaintext, so this closes a real gap consistent with the secrets-handling discipline already applied elsewhere in this repo (see ADR-0004, ADR-0005).
- OpenTofu maintains command and HCL compatibility with Terraform, and shares the same provider ecosystem (including `bpg/proxmox`), so this decision carries effectively zero migration cost when adopted before any `.tf` code is written.
- Neutral, multi-vendor governance (Linux Foundation) avoids single-vendor control over the roadmap of a tool this repo depends on.

## Consequences
- CLI invocations use `tofu` instead of `terraform` throughout (local usage, CI workflows, documentation).
- The provisioning directory is named `opentofu/` rather than `terraform/` to reflect the actual tool in use.
- State files may use OpenTofu's native encryption once configured; the key management for that (a KMS, Vault, or passphrase-based key provider) will get its own decision when the OpenTofu module is actually built.
