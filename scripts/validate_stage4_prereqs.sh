#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

NS="staging"
CLUSTER="fastticket-eks"
REGION="us-east-1"
BACKEND_IMG="docker.io/fercanap/fastticket-backend:staging"
FRONTEND_IMG="docker.io/fercanap/fastticket-frontend:staging"

PASS=true

check_cmd(){ command -v "$1" >/dev/null 2>&1 && echo "[OK] $1" || { echo "[MISSING] $1"; PASS=false; }; }

echo "== Local tooling =="
check_cmd kubectl
check_cmd aws
check_cmd docker
check_cmd jq || true
check_cmd gh || true

mkdir -p logs reports

echo "\n== Repo structure =="
[ -d infra ] && echo "[OK] infra/ present" || { echo "[MISSING] infra/"; PASS=false; }
[ -d k8s/overlays/staging ] && echo "[OK] k8s/overlays/staging present" || { echo "[MISSING] k8s/overlays/staging"; PASS=false; }

echo "\n== Images exist in Docker Hub =="
if docker pull "$BACKEND_IMG" >/dev/null 2>&1; then echo "[OK] $BACKEND_IMG"; else echo "[WARN] Could not pull $BACKEND_IMG"; fi
if docker pull "$FRONTEND_IMG" >/dev/null 2>&1; then echo "[OK] $FRONTEND_IMG"; else echo "[WARN] Could not pull $FRONTEND_IMG"; fi

echo "\n== AWS/EKS access (optional locally) =="
set +e
aws sts get-caller-identity >/dev/null 2>&1 && echo "[OK] aws sts works" || echo "[INFO] aws sts not available locally (OK for runners)."
aws eks update-kubeconfig --name "$CLUSTER" --region "$REGION" >/dev/null 2>&1 && echo "[OK] kubeconfig updated for $CLUSTER" || echo "[INFO] Skipping kubeconfig update locally."
kubectl get ns "$NS" >/dev/null 2>&1 && echo "[OK] namespace $NS present" || echo "[INFO] Could not verify namespace locally."
set -e

cat <<EOF

== DAST target ==
Runner will:\n  1) Configure AWS credentials via OIDC\n  2) Update kubeconfig for $CLUSTER ($REGION)\n  3) Port-forward backend: kubectl -n $NS port-forward deploy/backend 8080:8000\n  4) ZAP Baseline target: http://127.0.0.1:8080

If you prefer a different port or path, set these repo variables:
  - DAST_TARGET_URL (default: http://127.0.0.1:8080)
  - DAST_HEALTH_PATH (default: /health)
  - AWS_REGION (default: us-east-1)
EOF

if [ "$PASS" = true ]; then
  echo "\nRESULT: PASS - Stage 4 prerequisites look OK."
else
  echo "\nRESULT: WARN/FAIL - Please address missing items above."
fi
