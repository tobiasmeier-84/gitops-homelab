# bootstrap

The single root ArgoCD Application. Points at `gitops/apps/` so that every workload Application is discovered and synced automatically — this is the one thing installed manually (via `ansible/roles/argocd-bootstrap`); everything else flows from here.
