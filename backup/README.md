# backup

Source for the backup CronJob: `image/` holds the Dockerfile and backup script (see ADR-0005, ADR-0006 in `docs/adr/`) built and pushed by `.github/workflows/backup-image.yml`. The Kubernetes CronJob manifest itself lives in `gitops/apps/backup/`.
