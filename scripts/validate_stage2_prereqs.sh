#!/usr/bin/env bash
set -euo pipefail

# validate_stage2_prereqs.sh
# Pre-validation for Stage 2: Kubernetes Deployment (staging)
# - Verifies kubectl context access to EKS cluster
# - Ensures namespaces do not already exist (idempotent-friendly)
# - Checks for StorageClass gp3 and AWS EBS CSI driver
# - Confirms node capacity
# - Checks Kustomize overlay images are configured (not placeholders)
# - Writes a concise summary and exits non-zero on hard blockers

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OVERLAY_DIR="${ROOT_DIR}/k8s/overlays/staging"
LOG_DIR="${ROOT_DIR}/logs"
mkdir -p "${LOG_DIR}"

YELLOW='\033[1;33m'; GREEN='\033[0;32m'; RED='\033[0;31m'; NC='\033[0m'
info(){ echo -e "${YELLOW}➤${NC} $*"; }
ok(){ echo -e "${GREEN}OK${NC} - $*"; }
fail(){ echo -e "${RED}FAIL${NC} - $*"; }

TS="$(date +%Y%m%d-%H%M%S)"
SUMMARY=( )
FAILURES=0

section(){ echo -e "\n===== $* ====="; }

section "Stage 2 prereqs"

# 1) kubectl context and cluster access
info "Checking kubectl context..."
if ! kubectl config current-context >/dev/null 2>&1; then
  fail "kubectl context not set. Run: aws eks update-kubeconfig --region <region> --name fastticket-eks"
  exit 1
fi
CURRENT_CTX=$(kubectl config current-context || true)
info "Current context: ${CURRENT_CTX}"

# 2) Confirm EKS cluster is reachable
info "Checking cluster nodes..."
if ! kubectl get nodes -o wide | tee "${LOG_DIR}/stage2_nodes_${TS}.log"; then
  fail "Cluster not reachable"
  exit 1
fi
ok "Cluster reachable"

# 3) Namespaces existence
for ns in dev staging; do
  if kubectl get ns "$ns" >/dev/null 2>&1; then
    info "Namespace '$ns' already exists (idempotent safe)"
  else
    ok "Namespace '$ns' not present yet (will be created by kustomize)"
  fi
done

# 4) StorageClass and EBS CSI driver
info "Checking StorageClasses..."
SC_LIST=$(kubectl get sc -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' || true)
echo "$SC_LIST" | tee "${LOG_DIR}/stage2_storageclasses_${TS}.log" >/dev/null
if echo "$SC_LIST" | grep -q '^gp3$'; then
  ok "Found StorageClass 'gp3'"
else
  fail "StorageClass 'gp3' not found. A PVC with storageClassName: gp3 will not bind."
  echo "Tip: Install EBS CSI addon and create a gp3 StorageClass, e.g. 'gp3' as default."
  ((FAILURES++))
fi

info "Checking AWS EBS CSI add-on..."
REGION=$(aws configure get region || echo "us-east-1")
if aws eks describe-addon --cluster-name fastticket-eks --addon-name aws-ebs-csi-driver --region "$REGION" >/dev/null 2>&1; then
  ok "aws-ebs-csi-driver add-on is installed"
else
  fail "aws-ebs-csi-driver add-on is NOT installed"
  echo "You can install it now: aws eks create-addon --cluster-name fastticket-eks --addon-name aws-ebs-csi-driver --resolve-conflicts OVERWRITE --region $REGION"
  ((FAILURES++))
fi

# 5) Node capacity summary
info "Summarizing node capacity..."
kubectl get nodes -o json | jq -r '.items[] | "\(.metadata.name) CPU=\(.status.capacity.cpu) MEM=\(.status.capacity.memory)"' | tee "${LOG_DIR}/stage2_node_capacity_${TS}.log" || true

# 6) Check overlay images are configured
info "Validating overlay images..."
BACKEND_IMG=$(yq '.images[] | select(.name == "fastticket-backend") | .newName' "${OVERLAY_DIR}/kustomization.yaml" 2>/dev/null || echo "REPLACE_ME_BACKEND_IMAGE")
FRONTEND_IMG=$(yq '.images[] | select(.name == "fastticket-frontend") | .newName' "${OVERLAY_DIR}/kustomization.yaml" 2>/dev/null || echo "REPLACE_ME_FRONTEND_IMAGE")

if [[ "$BACKEND_IMG" == REPLACE_ME* ]]; then
  fail "Backend image not set in overlays/staging/kustomization.yaml (images.newName)."
  echo "Set it to your registry path, e.g., ghcr.io/<org>/fastticket-backend:tag"
  ((FAILURES++))
else
  ok "Backend image set: ${BACKEND_IMG}"
fi
if [[ "$FRONTEND_IMG" == REPLACE_ME* ]]; then
  fail "Frontend image not set in overlays/staging/kustomization.yaml (images.newName)."
  echo "Set it to your registry path, e.g., ghcr.io/<org>/fastticket-frontend:tag"
  ((FAILURES++))
else
  ok "Frontend image set: ${FRONTEND_IMG}"
fi

# 7) Summarize
if (( FAILURES > 0 )); then
  echo
  fail "Prerequisites check found ${FAILURES} blocking issue(s)."
  echo "Please address them, then re-run this script."
  exit 2
fi

echo
ok "All Stage 2 prerequisites satisfied. You can deploy with: kubectl apply -k k8s/overlays/staging"
