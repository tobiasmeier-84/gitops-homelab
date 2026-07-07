# Architecture Decisions — Full Decision Log

This document is the single source of truth for the design decisions behind this home-lab platform. It exists so that every non-obvious choice — including the ones where a real risk was knowingly accepted — is explained, not just implemented. Individual decisions with significant reasoning are broken out as standalone ADRs in [`docs/adr/`](adr/); this file is the consolidated summary.

## Scope

The platform: a 3-node Proxmox cluster running a new production-grade RKE2 Kubernetes cluster (for Nextcloud and similar workloads), fully defined as code (Terraform, Ansible, GitOps manifests) in a public git repository, with encrypted secrets, automated cross-provider backups, and a monitoring stack.

The single governing principle across every decision in this document: **if this repository and the credentials for the external providers it depends on survived a total loss of the physical hardware, the entire platform — hypervisor layer included — should be reconstructable from git alone.**

## Decision log

| Layer | Item | Decision | ADR |
|---|---|---|---|
| Hardware | Power protection | Include — UPS (Eaton); automated graceful shutdown (NUT) backlogged | — |
| Hardware | Out-of-band management (IPMI) | Accept risk | [0008](adr/0008-out-of-band-management-risk-accepted.md) |
| Hardware | 10G NIC / switch redundancy | Accept risk for now | [0009](adr/0009-nic-switch-redundancy-risk-accepted.md) |
| Hardware | Proxmox boot disk redundancy | Include — ZFS mirror, full reinstall | — |
| Hardware | Proxmox host provisioning | Include — automated answer-file ISO install | — |
| Hardware | Traffic segregation | Include — 10G for Longhorn/cluster, 1G for mgmt/ingress (VLAN-separated) | — |
| Network/Platform | Time synchronization | Include — chrony on all nodes, router as NTP source | — |
| Network/Platform | DNS & certificate issuance | Include | [0007](adr/0007-dns-certs-cloudflare.md) |
| Network/Platform | Container registry cache | Include — pull-through registry mirror | — |
| Cluster/GitOps | Kubernetes distribution | RKE2 | [0001](adr/0001-why-rke2-over-k3s.md) |
| Cluster/GitOps | Infrastructure-as-Code tool | OpenTofu over Terraform | [0010](adr/0010-opentofu-over-terraform.md) |
| Cluster/GitOps | Storage | Longhorn | [0002](adr/0002-why-longhorn-over-ceph.md) |
| Cluster/GitOps | GitOps delivery | ArgoCD, app-of-apps | [0003](adr/0003-argocd-app-of-apps.md) |
| Cluster/GitOps | Secrets management | SOPS + age | [0004](adr/0004-sops-age-secrets.md) |
| Cluster/GitOps | Reconstructability audit | Include — checklist run per app before onboarding | — |
| Cluster/GitOps | Repository resilience | Include — mirrored to self-hosted Gitea/GitLab | — |
| Cluster/GitOps | CI validation | Include — required checks before merge | — |
| Cluster/GitOps | OS patch/reboot orchestration | Include — Kured | — |
| Backup | Backup design | Dual-chain, cross-provider, per-run encryption | [0005](adr/0005-backup-design.md) |
| Backup | Backup orchestration | Kubernetes CronJob | [0006](adr/0006-backup-orchestration-cronjob.md) |
| Observability | Monitoring stack | kube-prometheus-stack + Loki | — |
| Observability | Backup failure/staleness alerting | Include | — |
| Observability | Restore drills | Include — scheduled, automated | — |
| Observability | Metrics/log retention | Include — explicit limits, sized to available disk | — |
| Security | NetworkPolicies | Include — default-deny per namespace, explicit allows | — |
| Security | Perimeter protection | Include — CrowdSec in front of HAProxy | — |
