# homelab-k8s

A production-intent Kubernetes platform on a 3-node Proxmox home lab, built entirely as code: hypervisor provisioning, VM provisioning, cluster bootstrap, and every workload are all reconstructable from this repository alone.

This repo exists as a working reference for platform-engineering practice — every non-trivial decision, including the ones where a real risk was knowingly accepted, is documented in [`docs/adr/`](docs/adr/).

## Guiding principle

If this repository and the credentials for the external providers it depends on (Cloudflare, backup storage/key providers, container registry) survived a total loss of the physical hardware, the entire platform should be reconstructable from git alone — hypervisor layer included.

## Stack overview

| Concern | Tool |
|---|---|
| Hypervisor | Proxmox VE (3 physical nodes), automated answer-file ISO install |
| VM provisioning | OpenTofu (`bpg/proxmox` provider) |
| VM/OS configuration | Ansible |
| Kubernetes distribution | RKE2 (3-node, combined control-plane + worker) |
| Storage | Longhorn, replica count 3, dedicated per-node disks |
| GitOps delivery | ArgoCD, app-of-apps pattern |
| Secrets | SOPS + age, decrypted at ArgoCD sync time |
| Ingress | ingress-nginx, fronted by existing HAProxy + VRRP VIP |
| DNS / certificates | Cloudflare, cert-manager DNS-01, CronJob-based DDNS updater |
| Naming convention | Belt objects (hosts), Stations (network), Saturn moons (VMs), Ships (workloads) — see ADR-0035 |
| Container registry | Harbor (pull-through cache + vulnerability scanning) |
| Identity / SSO | Microsoft Entra ID — native OIDC (Proxmox, Kubernetes API, ArgoCD, Grafana, Harbor, Nextcloud) + oauth2-proxy for services without native support |
| Monitoring | kube-prometheus-stack (Prometheus, Grafana, Alertmanager) + Loki |
| Backups | Dual-chain, cross-provider, per-run-encrypted PV backups (see ADR-0005) |
| OS patching | Kured (automated cordon/drain/reboot/uncordon) |
| Perimeter | CrowdSec in front of HAProxy |
| Authorization | Entra ID groups mapped to Kubernetes RBAC, ArgoCD RBAC, and Harbor project roles |
| Image provenance | cosign signing, enforced via admission-controller policy |
| Dependency freshness | Renovate bot for Helm chart and image version updates |
| Network segmentation | 6 VLANs (MGMT/CLUSTER/STORAGE/DMZ-INGRESS/EGRESS + existing HOME), Cisco RV320 + HPE 1920/1950 |
| Naming convention | Belt objects (hosts), Stations (network), Saturn moons (VMs), Ships (workloads) — see ADR-0035 |

See [`docs/architecture-decisions.md`](docs/architecture-decisions.md) for the full decision log and [`docs/adr/`](docs/adr/) for individual, detailed ADRs.

## Repository layout

```
.
├── docs/
│   ├── architecture-decisions.md   # full decision log
│   ├── adr/                        # one file per significant decision
│   └── runbooks/                   # operational procedures (e.g. node reinstall)
├── proxmox-host/
│   ├── answer.toml.j2               # PVE 9.2 automated-install answer file template
│   ├── nodes.yaml                   # per-node values (ceres/eros/pallas)
│   ├── secrets/                     # SOPS-encrypted root password hash
│   └── render.py                    # renders per-node .toml from template + data
├── opentofu/
│   ├── modules/proxmox-vm/         # reusable VM provisioning module
│   └── environments/prod/          # the actual 3-node RKE2 cluster's VMs
├── ansible/
│   ├── inventory/
│   └── roles/
│       ├── common/                 # base hardening, chrony, users
│       ├── rke2/                   # RKE2 install + join
│       ├── longhorn-disk/          # prepares the dedicated Longhorn block device
│       └── argocd-bootstrap/       # one-time ArgoCD install, points at gitops/bootstrap
├── gitops/
│   ├── bootstrap/                  # the ArgoCD "app of apps" root Application
│   └── apps/                       # one folder per ArgoCD-managed workload
├── backup/
│   └── image/                      # Dockerfile + script for the backup CronJob image
└── .github/workflows/              # CI: tofu validate/plan, ansible-lint, kubeconform, image build
```

## Status

Design phase. Terraform, Ansible, and GitOps manifests are being built out incrementally; see open issues / project board for current progress.

## License

MIT — see [`LICENSE`](LICENSE).
