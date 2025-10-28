#!/usr/bin/env bash
set -euo pipefail

NS="staging"
echo "== Cleaning up public LoadBalancer Services (to stop ELB costs) =="
kubectl -n "$NS" delete svc backend-public --ignore-not-found
kubectl -n "$NS" delete svc frontend-public --ignore-not-found
echo "Done."
