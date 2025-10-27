#!/usr/bin/env bash
set -euo pipefail

CLUSTER_NAME=${CLUSTER_NAME:-fastticket-eks}
REGION=${REGION:-us-east-1}

TS=$(date +%Y%m%d-%H%M%S)
OUT_DIR="logs/ebs-csi/${TS}"
mkdir -p "${OUT_DIR}"

log(){ echo "[$(date +%Y-%m-%dT%H:%M:%S%z)] $*" | tee -a "${OUT_DIR}/run.log"; }

log "Starting EBS CSI repair and validation for ${CLUSTER_NAME} in ${REGION}"

set +e
bash scripts/ebs_csi_diag.sh 2>&1 | tee -a "${OUT_DIR}/diag.stdout" >/dev/null
set -e

bash scripts/ebs_csi_irsa_fix.sh 2>&1 | tee -a "${OUT_DIR}/irsa_fix.stdout"

sleep 10

log "Controller pods after IRSA fix"
kubectl -n kube-system get pods -l app.kubernetes.io/name=aws-ebs-csi-driver -o wide | tee -a "${OUT_DIR}/pods_after_fix.txt"

log "Controller logs (tail)"
kubectl -n kube-system logs deploy/ebs-csi-controller --all-containers --tail=200 | tee -a "${OUT_DIR}/controller_logs_after_fix.txt" || true

aws eks describe-addon --cluster-name "${CLUSTER_NAME}" --addon-name aws-ebs-csi-driver --region "${REGION}" --output json | tee "${OUT_DIR}/addon_after_fix.json" >/dev/null || true

bash scripts/ebs_csi_validate.sh 2>&1 | tee -a "${OUT_DIR}/validate.stdout"

log "EBS CSI repair and validation completed successfully. Logs in ${OUT_DIR}"
