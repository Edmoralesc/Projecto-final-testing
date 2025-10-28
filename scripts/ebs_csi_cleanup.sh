#!/usr/bin/env bash
set -euo pipefail

kubectl delete -f k8s/storage/test-pod.yaml --ignore-not-found
kubectl delete -f k8s/storage/test-pvc.yaml --ignore-not-found
# PV will be deleted if reclaimPolicy on the StorageClass is Delete

echo "Cleanup requested. Note: StorageClass gp3 is left in place." >&2
