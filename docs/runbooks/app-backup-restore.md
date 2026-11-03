# Restore a backup made by `app-backup` (forscher example)

**Status: tested on 2026-11-03** with the first real backup (forscher-20261103-115929): both chains
restored independently (key from the own vault), the two restores were identical and contained
forscher.db, -wal, -shm and photos/ (5532 KiB). Not yet tested: restoring into the live volume
(step 4) and the application starting on it. Repeat the drill after changes to the backup scripts. The self-test (`kubectl create job --from=cronjob/<app>-backup-selftest`) proves the
download+decrypt path with throwaway data, not with the real backup.

Backups exist for at most 13 days. Names are `<app>-YYYYMMDD-HHMMSS` (UTC).

1. Pick a name: `kubectl -n forscher logs job/<last backup job>` shows `name=...` on the RESULT line.
2. Start a restore pod (restricted-compliant, has the credentials and the scripts):
   ```
   kubectl -n forscher apply -f - <<'EOF'
   apiVersion: v1
   kind: Pod
   metadata:
     name: forscher-restore
     labels: { app.kubernetes.io/part-of: forscher-backup }
   spec:
     restartPolicy: Never
     securityContext: { runAsNonRoot: true, runAsUser: 10001, runAsGroup: 10001, seccompProfile: { type: RuntimeDefault } }
     containers:
       - name: restore
         image: alpine/k8s:1.30.3
         command: ["sleep", "3600"]
         securityContext: { allowPrivilegeEscalation: false, capabilities: { drop: ["ALL"] } }
         envFrom: [ { secretRef: { name: backup-chain-credentials } } ]
         env:
           - { name: APP_NAME, value: forscher }
           - { name: MAX_AGE_DAYS, value: "13" }
           - { name: BUCKET_A, value: scopuli-chain-a-backup }
           - { name: EP_A, value: "https://s3.eu-west-par.io.cloud.ovh.net" }
           - { name: BUCKET_B, value: barbapiccola-chain-b-backup }
           - { name: EP_B, value: "https://s3.eu-central-003.backblazeb2.com" }
         volumeMounts: [ { name: scripts, mountPath: /scripts }, { name: work, mountPath: /work } ]
     volumes:
       - { name: scripts, configMap: { name: forscher-backup-scripts } }
       - { name: work, emptyDir: { sizeLimit: 2Gi } }
   EOF
   ```
3. Download and decrypt (chain A; use `B` if A is unavailable):
   ```
   kubectl -n forscher exec forscher-restore -- sh -c '. /scripts/chain-lib.sh && tools_setup && chain_fetch A <NAME> /work/restore.zst && mkdir -p /work/out && $ZSTD -dc /work/restore.zst | tar -xf - -C /work/out && ls -la /work/out'
   ```
4. Scale the app down, copy the files into the volume (`kubectl cp` from the restore pod into a pod that
   mounts `forscher-data`), fix ownership to uid/gid 10001, scale the app up. The `-wal` file must be
   restored together with the database file.
5. `kubectl -n forscher delete pod forscher-restore`.

Note: `tools_setup` installs the tools into a private folder; call them as `$ZSTD`, `$AGE`, `$JQ` after sourcing
`/scripts/chain-lib.sh` (they are not on PATH).
