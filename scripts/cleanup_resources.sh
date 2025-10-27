#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

NS="staging"
CLUSTER="fastticket-eks"
REGION="us-east-1"

cat << EOF
Cleanup options (choose carefully):
  1) Delete Kubernetes namespace '$NS' only
  2) Terraform destroy (infra/, will tear down EKS and related resources)
  3) Exit (do nothing)
EOF

read -rp "Enter choice [1-3]: " choice

case "$choice" in
  1)
    read -rp "Confirm delete namespace '$NS'? (y/N): " ans
    if [[ "$ans" =~ ^[Yy]$ ]]; then
      aws eks update-kubeconfig --name "$CLUSTER" --region "$REGION" || true
      kubectl delete ns "$NS" --wait=false || true
      echo "Requested deletion of namespace $NS"
    else
      echo "Aborted."
    fi
    ;;
  2)
    read -rp "Confirm Terraform destroy infra/? (y/N): " ans
    if [[ "$ans" =~ ^[Yy]$ ]]; then
      (cd infra && terraform destroy -auto-approve)
    else
      echo "Aborted."
    fi
    ;;
  *)
    echo "No action taken."
    ;;
 esac
