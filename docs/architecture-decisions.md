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
| Network/Platform | Container registry cache | Harbor | [0017](adr/0017-harbor-over-plain-registry-mirror.md) |
| Cluster/GitOps | Kubernetes distribution | RKE2 | [0001](adr/0001-why-rke2-over-k3s.md) |
| Cluster/GitOps | Storage | Longhorn | [0002](adr/0002-why-longhorn-over-ceph.md) |
| Cluster/GitOps | GitOps delivery | ArgoCD over Flux | [0003](adr/0003-argocd-app-of-apps.md), [0011](adr/0011-argocd-over-flux.md) |
| Cluster/GitOps | Secrets management | SOPS + age | [0004](adr/0004-sops-age-secrets.md) |
| Cluster/GitOps | Infrastructure-as-Code tool | OpenTofu over Terraform | [0010](adr/0010-opentofu-over-terraform.md) |
| Cluster/GitOps | OpenTofu Proxmox provider | bpg/proxmox over telmate/proxmox | [0012](adr/0012-bpg-over-telmate-proxmox-provider.md) |
| Cluster/GitOps | CNI | Canal over Cilium | [0013](adr/0013-canal-over-cilium.md) |
| Cluster/GitOps | Reconstructability audit | Include — checklist run per app before onboarding | — |
| Cluster/GitOps | Repository resilience | Include — mirrored to self-hosted Gitea/GitLab | — |
| Cluster/GitOps | CI validation | Include — required checks before merge | — |
| Cluster/GitOps | OS patch/reboot orchestration | Kured over unattended-upgrades alone | [0015](adr/0015-kured-over-unattended-upgrades-alone.md) |
| Backup | Backup design | Dual-chain, cross-provider, per-run encryption | [0005](adr/0005-backup-design.md) |
| Backup | Backup orchestration | Kubernetes CronJob | [0006](adr/0006-backup-orchestration-cronjob.md) |
| Observability | Monitoring stack | kube-prometheus-stack over VictoriaMetrics, + Loki | [0016](adr/0016-kube-prometheus-stack-over-victoriametrics.md) |
| Observability | Backup failure/staleness alerting | Include | — |
| Observability | Restore drills | Include — scheduled, automated | — |
| Observability | Metrics/log retention | Include — explicit limits, sized to available disk | — |
| Security | NetworkPolicies | Include — default-deny per namespace, explicit allows | — |
| Security | Perimeter protection | CrowdSec over fail2ban | [0014](adr/0014-crowdsec-over-fail2ban.md) |
| Security | Identity/SSO scope | Entra ID via native OIDC where supported | [0018](adr/0018-entraid-sso-integration-scope.md) |
| Security | Auth for services without native OIDC | oauth2-proxy (Longhorn UI, Prometheus/Alertmanager, HAProxy stats) | [0019](adr/0019-oauth2-proxy-for-unauthenticated-services.md) |
| Security | SSH access SSO | Accept risk (backlogged) — key-based access continues | [0020](adr/0020-ssh-entraid-backlogged.md) |
| Cluster/GitOps | OpenTofu state backend | Self-hosted, bootstrapped first (breaks circular dependency) | [0024](adr/0024-self-hosted-opentofu-state-backend.md) |
| Cluster/GitOps | Bootstrap ordering | Explicit documented first-boot sequence | [0025](adr/0025-bootstrap-ordering-runbook.md) |
| Cluster/GitOps | Resource governance | Explicit requests/limits + per-namespace ResourceQuotas | [0026](adr/0026-resource-requests-limits-quotas.md) |
| Cluster/GitOps | Dependency freshness | Renovate bot for Helm/image version updates | [0027](adr/0027-renovate-dependency-updates.md) |
| Cluster/GitOps | Disaster-recovery validation | Full tested end-to-end DR runbook | [0023](adr/0023-tested-disaster-recovery-runbook.md) |
| Backup | Backup consistency | Application-consistent (Longhorn freeze hooks) for DB volumes | [0022](adr/0022-application-consistent-backups.md) |
| Observability | External availability check | Third-party dead-man's-switch heartbeat | [0028](adr/0028-external-dead-mans-switch.md) |
| Observability | Certificate renewal monitoring | Explicit alert on renewal failure | [0029](adr/0029-cert-renewal-failure-alerting.md) |
| Security | Authorization mapping | Entra ID groups \u2192 Kubernetes/ArgoCD/Harbor RBAC | [0021](adr/0021-entraid-group-authorization-mapping.md) |
| Security | Image provenance | cosign signing + admission-controller enforcement | [0030](adr/0030-image-signing-admission-control.md) |
| Network/Platform | VLAN segmentation design | 6 VLANs (HOME/MGMT/CLUSTER/STORAGE/DMZ-INGRESS/EGRESS) | [0031](adr/0031-vlan-network-segmentation.md) |
| Hardware | Perimeter firewall (RV320) | Accept EOL risk, backlog upgrade | [0032](adr/0032-rv320-eol-risk-accepted.md) |
| Network/Platform | Network device config tracking | Out of IaC scope, manual GUI config only | [0033](adr/0033-network-device-config-out-of-iac-scope.md) |
| Cluster/GitOps | Initial rebuild strategy | Greenfield full-cluster rebuild over rolling migration | [0034](adr/0034-greenfield-rebuild-over-rolling-migration.md) |
| Network/Platform | Naming convention | Four thematic tiers (Belt/Stations/Saturn moons/Ships) under solsys.dev | [0035](adr/0035-naming-convention.md) |