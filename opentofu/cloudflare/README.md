## Initializing (first time, or after any backend config change)

The S3 backend intentionally has no credentials in the committed
`versions.tf` — pass them explicitly at init time:

​```bash
source ~/homelab-env.sh
tofu init \
  -backend-config="access_key=$MINIO_ROOT_USER" \
  -backend-config="secret_key=$MINIO_ROOT_PASSWORD"
​```