# CI workflows

- `terraform-ci.yml` — terraform fmt/validate/plan on PRs touching `terraform/`
- `ansible-lint.yml` — ansible-lint on PRs touching `ansible/`
- `kubeconform.yml` — schema validation of manifests under `gitops/`
- `backup-image.yml` — builds and pushes the backup CronJob image (`backup/image/`) to ghcr.io, tagged by commit SHA
- `mirror.yml` — pushes the repo to the secondary Gitea/GitLab remote

All are required checks before merge (see ADR log, Cluster/GitOps layer).
