#!/usr/bin/env bash
set -euo pipefail

log(){ echo "[$(date +%Y-%m-%dT%H:%M:%S%z)] $*"; }

log "Ensuring StorageClass gp3 exists (idempotent)"
if ! kubectl get sc gp3 >/dev/null 2>&1; then
	kubectl apply -f k8s/storage/gp3-sc.yaml
else
	log "StorageClass gp3 already present; skipping apply"
fi

log "Recreating test Pod to ensure fresh run"
kubectl delete -f k8s/storage/test-pod.yaml --ignore-not-found

log "Applying PVC and Pod for dynamic provisioning test"
kubectl apply -f k8s/storage/test-pvc.yaml
kubectl apply -f k8s/storage/test-pod.yaml

log "Waiting for PVC phase=Bound"
kubectl wait --for=jsonpath='{.status.phase}'=Bound pvc/test-pvc --timeout=3m

log "Waiting for Pod to be Ready"
kubectl wait --for=condition=Ready pod/test-pod --timeout=3m

kubectl get pvc,pv -o wide
kubectl get pod test-pod -o wide

log "Validation succeeded"
