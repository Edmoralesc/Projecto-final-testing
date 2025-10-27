#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
NS="staging"
SVC_FILE="${ROOT_DIR}/k8s/public/services.yaml"

echo "== Exposing backend and frontend via AWS LoadBalancer Services =="
kubectl get ns "$NS" >/dev/null 2>&1 || { echo "Namespace $NS missing"; exit 1; }

kubectl apply -f "$SVC_FILE"

get_lb_host(){
  local name="$1"
  local host ip
  for i in {1..40}; do
    host=$(kubectl -n "$NS" get svc "$name" -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)
    ip=$(kubectl -n "$NS" get svc "$name" -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)
    if [[ -n "$host" ]]; then echo "$host"; return 0; fi
    if [[ -n "$ip" ]]; then echo "$ip"; return 0; fi
    sleep 6
  done
  return 1
}

echo "Waiting for backend-public EXTERNAL-IP..."
BACKEND_HOST=$(get_lb_host backend-public) || { echo "Timed out waiting for backend-public"; exit 2; }
echo "backend-public: $BACKEND_HOST"

echo "Waiting for frontend-public EXTERNAL-IP..."
FRONTEND_HOST=$(get_lb_host frontend-public) || { echo "Timed out waiting for frontend-public"; exit 2; }
echo "frontend-public: $FRONTEND_HOST"

cat <<EOF

Public endpoints ready:
- Backend:  http://$BACKEND_HOST/health
- Frontend: http://$FRONTEND_HOST/

Use the validate script to test HTTP access:
  bash scripts/validate_public_access.sh
EOF
