#!/bin/sh
# Orchestrator of one backup run (ADR-0054). Runs as the CronJob pod with kubectl:
#   snapshot of the app's PVC -> clone -> worker pod (backup.sh) -> logs -> cleanup -> mail
# The snapshot is one frozen moment; the app keeps running, nothing is paused.
set -u

: "${APP_NAME:?}" "${NAMESPACE:?}" "${PVC_NAME:?}" "${WORKER_RUN_AS_USER:?}" "${IMAGE:?}"
WORKER_RUN_AS_GROUP="${WORKER_RUN_AS_GROUP:-$WORKER_RUN_AS_USER}"
RUN_ID=$(date -u +%Y%m%d-%H%M%S)   # UTC; becomes part of the backup name, so its age is readable from it
SNAP="${APP_NAME}-snap-${RUN_ID}"
CLONE="${APP_NAME}-clone-${RUN_ID}"
POD="${APP_NAME}-backup-worker-${RUN_ID}"
LABEL="backup-job=${APP_NAME}-backup"
LOG=/tmp/worker-output.log
STATUS="FAILED"
RESULT="no result line (the worker did not finish)"
: >"$LOG"

log() { msg="$(date -u +%Y-%m-%dT%H:%M:%SZ) $*"; echo "$msg"; echo "$msg" >>"$LOG"; }

delete_labelled() { # leftovers of crashed earlier runs (concurrencyPolicy is Forbid, so any are stale)
  for kind in pod pvc volumesnapshot; do
    for obj in $(kubectl get "$kind" -n "$NAMESPACE" -l "$LABEL" -o name 2>/dev/null); do
      log "Removing leftover $obj of an earlier run"
      kubectl delete "$obj" -n "$NAMESPACE" --ignore-not-found=true || true
    done
  done
}

notify() {
  _send=no
  if [ "$STATUS" != "OK" ] || [ "${DRY_RUN:-false}" = "true" ]; then _send=yes; fi
  if [ "$STATUS" = "OK" ] && [ "${NOTIFY_SUCCESS_WEEKDAY:-0}" != "0" ] && [ "$(date -u +%u)" = "${NOTIFY_SUCCESS_WEEKDAY:-0}" ]; then _send=yes; fi
  if [ "$_send" = yes ]; then
    export STATUS RESULT RUN_ID APP_NAME
    python3 /scripts-notify/notify.py || echo "WARNING: notification failed to send"
  else
    echo "Success, no mail today (heartbeat weekday: ${NOTIFY_SUCCESS_WEEKDAY:-0})"
  fi
}

cleanup() {
  log "Cleaning up..."
  if kubectl get pod "$POD" -n "$NAMESPACE" >/dev/null 2>&1; then
    {
      echo "=== worker pod log ==="
      kubectl logs "$POD" -n "$NAMESPACE" --timestamps 2>&1
    } >>"$LOG" || true
    kubectl delete pod "$POD" -n "$NAMESPACE" --ignore-not-found=true || true
  fi
  kubectl delete pvc "$CLONE" -n "$NAMESPACE" --ignore-not-found=true || true
  kubectl delete volumesnapshot "$SNAP" -n "$NAMESPACE" --ignore-not-found=true || true
  log "RESULT - $STATUS: $RESULT"
  notify
}
trap cleanup EXIT
trap 'exit 143' TERM INT

# Waits until the pod has Succeeded (0) or Failed/timed out (1).
wait_pod() { # pod timeout_seconds
  _e=0
  while [ "$_e" -lt "$2" ]; do
    _ph=$(kubectl get pod "$1" -n "$NAMESPACE" -o jsonpath='{.status.phase}' 2>/dev/null || echo "")
    [ "$_ph" = "Succeeded" ] && return 0
    [ "$_ph" = "Failed" ] && return 1
    sleep 5
    _e=$((_e + 5))
  done
  log "wait_pod: timed out after ${2}s waiting for $1"
  return 1
}

log "Backup run $RUN_ID for $APP_NAME (pvc $PVC_NAME, dry run: ${DRY_RUN:-false}, maximum age ${MAX_AGE_DAYS:-13} days)"
delete_labelled

log "Taking the snapshot"
kubectl apply -f - <<EOF || { RESULT="snapshot could not be created"; exit 1; }
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshot
metadata:
  name: $SNAP
  namespace: $NAMESPACE
  labels:
    backup-job: ${APP_NAME}-backup
spec:
  volumeSnapshotClassName: ${SNAPSHOT_CLASS:-longhorn-snapshot-vsc}
  source:
    persistentVolumeClaimName: $PVC_NAME
EOF

_e=0; READY=no
while [ "$_e" -lt 180 ]; do
  [ "$(kubectl get volumesnapshot "$SNAP" -n "$NAMESPACE" -o jsonpath='{.status.readyToUse}' 2>/dev/null || echo "")" = "true" ] && { READY=yes; break; }
  sleep 3; _e=$((_e + 3))
done
[ "$READY" = yes ] || { RESULT="snapshot never became ready"; exit 1; }
SIZE=$(kubectl get volumesnapshot "$SNAP" -n "$NAMESPACE" -o jsonpath='{.status.restoreSize}' 2>/dev/null || echo "")
[ -n "$SIZE" ] || SIZE=$(kubectl get pvc "$PVC_NAME" -n "$NAMESPACE" -o jsonpath='{.status.capacity.storage}')
log "Snapshot ready (size $SIZE)"

kubectl apply -f - <<EOF || { RESULT="clone volume could not be created"; exit 1; }
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: $CLONE
  namespace: $NAMESPACE
  labels:
    backup-job: ${APP_NAME}-backup
spec:
  storageClassName: ${CLONE_STORAGE_CLASS:-longhorn-general-single-replica}
  dataSource:
    name: $SNAP
    kind: VolumeSnapshot
    apiGroup: snapshot.storage.k8s.io
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: $SIZE
EOF

log "Starting the worker pod"
kubectl apply -f - <<EOF || { RESULT="worker pod could not be created"; exit 1; }
apiVersion: v1
kind: Pod
metadata:
  name: $POD
  namespace: $NAMESPACE
  labels:
    backup-job: ${APP_NAME}-backup
    app.kubernetes.io/part-of: ${APP_NAME}-backup
spec:
  restartPolicy: Never
  activeDeadlineSeconds: 3000
  securityContext:
    runAsNonRoot: true
    runAsUser: $WORKER_RUN_AS_USER
    runAsGroup: $WORKER_RUN_AS_GROUP
    fsGroup: $WORKER_RUN_AS_GROUP
    seccompProfile:
      type: RuntimeDefault
  containers:
    - name: worker
      image: $IMAGE
      securityContext:
        allowPrivilegeEscalation: false
        capabilities:
          drop: ["ALL"]
      envFrom:
        - secretRef:
            name: backup-chain-credentials
      env:
        - name: APP_NAME
          value: "$APP_NAME"
        - name: RUN_ID
          value: "$RUN_ID"
        - name: DRY_RUN
          value: "${DRY_RUN:-false}"
        - name: MAX_AGE_DAYS
          value: "${MAX_AGE_DAYS:-13}"
        - name: CHUNK_MIB
          value: "${CHUNK_MIB:-512}"
        - name: UPLOAD_MAX_BANDWIDTH_KBPS
          value: "${UPLOAD_MAX_BANDWIDTH_KBPS:-0}"
        - name: BUCKET_A
          value: "$BUCKET_A"
        - name: EP_A
          value: "$EP_A"
        - name: BUCKET_B
          value: "$BUCKET_B"
        - name: EP_B
          value: "$EP_B"
      command: ["/bin/sh", "/scripts/backup.sh"]
      resources:
        requests:
          cpu: 50m
          memory: 128Mi
        limits:
          memory: 1Gi
      volumeMounts:
        - name: clone-data
          mountPath: /data
          readOnly: true
        - name: work
          mountPath: /work
        - name: scripts
          mountPath: /scripts
  volumes:
    - name: clone-data
      persistentVolumeClaim:
        claimName: $CLONE
    - name: work
      emptyDir:
        sizeLimit: ${WORK_DIR_SIZE:-2Gi}
    - name: scripts
      configMap:
        name: ${APP_NAME}-backup-scripts
EOF

if wait_pod "$POD" 3000; then
  STATUS="OK"
else
  STATUS="FAILED"
fi
_line=$(kubectl logs "$POD" -n "$NAMESPACE" 2>/dev/null | grep ' RESULT - ' | tail -1 | sed 's/^[^ ]* RESULT - //')
[ -n "$_line" ] && RESULT="$_line"
[ "$STATUS" = "OK" ] || exit 1
exit 0
