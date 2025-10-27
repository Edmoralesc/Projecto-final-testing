#!/usr/bin/env bash
set -euo pipefail

CLUSTER_NAME=${CLUSTER_NAME:-fastticket-eks}
REGION=${REGION:-us-east-1}

TS=$(date +%Y%m%d-%H%M%S)
OUT_DIR="logs/ebs-csi/${TS}"
mkdir -p "${OUT_DIR}"

log(){ echo "[$(date +%Y-%m-%dT%H:%M:%S%z)] $*" | tee -a "${OUT_DIR}/diag.log"; }

log "Collecting OIDC issuer for cluster ${CLUSTER_NAME} in ${REGION}"
OIDC_ISSUER=$(aws eks describe-cluster --name "${CLUSTER_NAME}" --region "${REGION}" --query "cluster.identity.oidc.issuer" --output text 2>&1 | tee "${OUT_DIR}/oidc_issuer.txt") || true

log "Listing IAM OIDC providers"
aws iam list-open-id-connect-providers | tee "${OUT_DIR}/iam_oidc_providers.json" >/dev/null || true

log "Describing EBS CSI addon"
aws eks describe-addon --cluster-name "${CLUSTER_NAME}" --addon-name aws-ebs-csi-driver --region "${REGION}" --output json | tee "${OUT_DIR}/addon.json" >/dev/null || true

log "Getting ebs-csi resources in kube-system"
kubectl -n kube-system get deploy,ds,pods -l app.kubernetes.io/name=aws-ebs-csi-driver -o wide | tee "${OUT_DIR}/k8s_get.txt" || true

log "Describe ebs-csi-controller deploy"
kubectl -n kube-system describe deploy ebs-csi-controller | tee "${OUT_DIR}/deploy_describe.txt" || true

log "Logs from ebs-csi-controller (all containers, last 300 lines)"
kubectl -n kube-system logs deploy/ebs-csi-controller --all-containers --tail=300 | tee "${OUT_DIR}/controller_logs.txt" || true

log "Events mentioning EBS"
kubectl -n kube-system get events --sort-by=.lastTimestamp | grep -i ebs | tee "${OUT_DIR}/events.txt" || true

log "ServiceAccount manifest"
kubectl -n kube-system get sa ebs-csi-controller-sa -o yaml | tee "${OUT_DIR}/sa.yaml" || true

log "Diagnosis saved under ${OUT_DIR}"
