#!/usr/bin/env bash
# One-command deployment from zero: Infra (Terraform) + K8s apps + validations
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

export AWS_REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-us-east-1}}"
export CLUSTER_NAME="${CLUSTER_NAME:-fastticket-eks}"
TS="$(date +%Y%m%d-%H%M%S)"
OUT_DIR="$ROOT_DIR/validation_output/deploy/${TS}"
LOG_DIR="$ROOT_DIR/logs"
mkdir -p "$OUT_DIR" "$LOG_DIR"

LOG_FILE="$LOG_DIR/deploy_${TS}.log"
SUMMARY_JSON="$OUT_DIR/summary.json"

log() { echo "[$(date -Iseconds)] $*" | tee -a "$LOG_FILE"; }
err() { echo "[$(date -Iseconds)] [ERROR] $*" | tee -a "$LOG_FILE" >&2; }

precheck() {
  local ok=true
  for tool in aws jq kubectl terraform; do
    if ! command -v "$tool" >/dev/null 2>&1; then err "Missing $tool"; ok=false; fi
  done
  [ "$ok" = true ] || { err "Precheck failed"; exit 1; }
  log "aws: $(aws --version 2>&1 | head -n1)"
  log "kubectl: $(kubectl version --client=true 2>&1 | head -n1 || true)"
  log "terraform: $(terraform version | head -n1)"
  log "jq: $(jq --version)"
}

wait_for_cluster_active() {
  local timeout=${1:-900} # 15 minutes
  local start=$(date +%s)
  log "Waiting for EKS cluster $CLUSTER_NAME to be ACTIVE (timeout ${timeout}s)"
  while true; do
    if aws eks describe-cluster --name "$CLUSTER_NAME" --region "$AWS_REGION" --output json | jq -e '.cluster.status=="ACTIVE"' >/dev/null 2>&1; then
      log "EKS cluster is ACTIVE"
      break
    fi
    sleep 10
    local now=$(date +%s); (( now-start > timeout )) && { err "Timeout waiting for EKS ACTIVE"; return 1; }
  done
}

wait_for_nodes_ready() {
  local want=${1:-1}
  local timeout=${2:-900}
  local start=$(date +%s)
  log "Waiting for at least $want Ready node(s)"
  while true; do
    local ready=$(kubectl get nodes --no-headers 2>/dev/null | awk '$2 ~ /Ready/ {c++} END{print c+0}')
    if [ "${ready:-0}" -ge "$want" ]; then log "Nodes Ready: $ready"; break; fi
    sleep 10
    local now=$(date +%s); (( now-start > timeout )) && { err "Timeout waiting for Ready nodes"; return 1; }
  done
}

wait_rollout() {
  local kind="$1"; local name="$2"; local ns="$3"; local to="${4:-600}s"
  log "Waiting rollout for $kind/$name in ns=$ns (timeout $to)"
  kubectl -n "$ns" rollout status "$kind/$name" --timeout="$to" | tee -a "$LOG_FILE"
}

json_init() { echo '{}' >"$SUMMARY_JSON"; }
json_set() { jq "$1" "$SUMMARY_JSON" >"$SUMMARY_JSON.tmp" && mv "$SUMMARY_JSON.tmp" "$SUMMARY_JSON"; }

precheck
json_init
json_set '.status = "IN_PROGRESS"'

# Stage 1: Infra (Terraform)
log "Stage 1: Validating prerequisites"
if [ -x scripts/validate_stage1_prereqs.sh ]; then
  if ! scripts/validate_stage1_prereqs.sh | tee -a "$LOG_FILE"; then err "Stage1 prereqs failed"; exit 1; fi
fi

log "Stage 1: Terraform init/apply in infra/"
pushd infra >/dev/null
terraform init -upgrade | tee -a "$LOG_FILE"
terraform apply -auto-approve | tee -a "$LOG_FILE"
popd >/dev/null

log "Updating kubeconfig"
aws eks update-kubeconfig --name "$CLUSTER_NAME" --region "$AWS_REGION" | tee -a "$LOG_FILE"

wait_for_cluster_active 900
wait_for_nodes_ready 1 900

log "Stage 1: Infra validation"
if [ -x scripts/validate_stage1_infra.sh ]; then
  scripts/validate_stage1_infra.sh | tee -a "$LOG_FILE"
fi
json_set '.stage1_done = true'

# Stage 2: Kubernetes workloads
log "Stage 2: K8s prerequisites"
if [ -x scripts/validate_stage2_prereqs.sh ]; then
  scripts/validate_stage2_prereqs.sh | tee -a "$LOG_FILE"
fi

log "Stage 2: Applying k8s overlay (staging)"
kubectl apply -k k8s/overlays/staging | tee -a "$LOG_FILE"

# Wait for workloads
wait_rollout statefulset postgres staging 600
wait_rollout deploy backend staging 600
wait_rollout deploy frontend staging 600

log "Stage 2: Deployment validation"
if [ -x scripts/validate_stage2_deployment.sh ]; then
  scripts/validate_stage2_deployment.sh | tee -a "$LOG_FILE"
fi
json_set '.stage2_done = true'

json_set '.status = "PASS"'
log "Deployment from scratch completed. Summary: $SUMMARY_JSON"
