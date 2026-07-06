# GitOps

ArgoCD-managed cluster state. `bootstrap/` holds the single root "app of apps" Application; `apps/` holds one folder per workload, each with its own ArgoCD Application manifest and Helm values / raw manifests.
