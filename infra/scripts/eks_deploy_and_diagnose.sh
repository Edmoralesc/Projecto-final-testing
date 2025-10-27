#!/bin/bash
# eks_deploy_and_diagnose.sh
# Orchestrate terraform apply for EKS, wait for nodegroup ACTIVE, diagnose on failure.
set -euo pipefail

CLUSTER_NAME="${CLUSTER_NAME:-fastticket-eks}"
REGION="${AWS_REGION:-us-east-1}"
AZS_CSV="${AZS:-us-east-1a,us-east-1d}"
TIMEOUT_MIN="${TIMEOUT_MIN:-25}"
INFRA_DIR="${INFRA_DIR:-$(dirname "$0")/..}"

cd "$INFRA_DIR"

echo "Running terraform init/validate/apply in $INFRA_DIR ..."
terraform init -upgrade -input=false >/dev/null
terraform validate

set +e
terraform apply -auto-approve
APPLY_CODE=$?
set -e

# Always try to update kubeconfig after apply (cluster may exist)
aws eks update-kubeconfig --name "$CLUSTER_NAME" --region "$REGION" || true

# Wait for nodegroup status ACTIVE if apply succeeded; otherwise diagnose
NGS=$(aws eks list-nodegroups --cluster-name "$CLUSTER_NAME" --region "$REGION" --output text || true)
PRIMARY_NG="$(echo "$NGS" | head -n1)"

wait_for_ng() {
  local ng="$1"
  local end=$(( $(date +%s) + TIMEOUT_MIN*60 ))
  echo "Waiting up to ${TIMEOUT_MIN}m for nodegroup $ng to become ACTIVE..."
  while [[ $(date +%s) -lt $end ]]; do
    STATUS=$(aws eks describe-nodegroup --cluster-name "$CLUSTER_NAME" --nodegroup-name "$ng" --region "$REGION" --query 'nodegroup.status' --output text 2>/dev/null || echo creating)
    echo "Status: $STATUS"
    if [[ "$STATUS" == "ACTIVE" ]]; then return 0; fi
    sleep 30
  done
  return 1
}

if [[ $APPLY_CODE -ne 0 ]]; then
  echo "terraform apply failed (code $APPLY_CODE). Running diagnostics..." >&2
  bash ./eks_nodegroup_diagnose.sh -c "$CLUSTER_NAME" -r "$REGION" || true
  exit $APPLY_CODE
fi

if [[ -n "$PRIMARY_NG" ]]; then
  if ! wait_for_ng "$PRIMARY_NG"; then
    echo "Nodegroup did not become ACTIVE in time. Running diagnostics..." >&2
    bash ./eks_nodegroup_diagnose.sh -c "$CLUSTER_NAME" -n "$PRIMARY_NG" -r "$REGION" || true
    exit 3
  fi
fi

# Show nodes
kubectl get nodes -o wide || true

# Optional: run repository validation script if present
if [[ -f "$INFRA_DIR/validate_tf_aws.py" ]]; then
  python3 "$INFRA_DIR/validate_tf_aws.py" || true
fi

echo "Deployment finished."
