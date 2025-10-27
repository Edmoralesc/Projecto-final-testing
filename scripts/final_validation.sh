#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

NS="staging"
CLUSTER="fastticket-eks"
REGION="us-east-1"
SUMMARY="logs/final_validation_summary.log"
mkdir -p logs reports
: > "$SUMMARY"

log(){ echo "$*" | tee -a "$SUMMARY"; }
ok(){ log "[OK] $*"; }
warn(){ log "[WARN] $*"; }
fail(){ log "[FAIL] $*"; }

log "===== Stage 5 Final Validation ====="

# Stage 1: Infra validation
log "\n-- Stage 1: Infrastructure --"
if [ -f infra/validate_eks_stage1.sh ]; then
  if bash infra/validate_eks_stage1.sh >>"$SUMMARY" 2>&1; then ok "validate_eks_stage1.sh"; else fail "validate_eks_stage1.sh"; fi
else
  warn "infra/validate_eks_stage1.sh not found; running terraform validate"
  (cd infra && terraform validate) >>"$SUMMARY" 2>&1 || fail "terraform validate"
fi

# Stage 2: K8s deployment
log "\n-- Stage 2: Kubernetes Deployment --"
if bash scripts/validate_stage2_prereqs.sh >>"$SUMMARY" 2>&1 && bash scripts/validate_stage2_deployment.sh >>"$SUMMARY" 2>&1; then
  ok "Stage 2 validators passed"
else
  fail "Stage 2 validators failed"
fi

# Stage 3: CI/CD
log "\n-- Stage 3: CI/CD --"
if bash scripts/validate_stage3_prereqs.sh >>"$SUMMARY" 2>&1; then ok "Stage 3 prereqs"; else warn "Stage 3 prereqs issues"; fi
if bash scripts/validate_stage3_pipeline.sh >>"$SUMMARY" 2>&1; then ok "Stage 3 pipeline health"; else warn "Stage 3 pipeline health issues"; fi
if command -v gh >/dev/null 2>&1; then
  gh run list --workflow cd-staging.yml --limit 1 | tee -a "$SUMMARY" || true
else
  warn "gh not installed; cannot confirm CD run via API"
fi

# Stage 4: Security Gates
log "\n-- Stage 4: Security Gates --"
if bash scripts/validate_stage4_prereqs.sh >>"$SUMMARY" 2>&1; then ok "Stage 4 prereqs"; else warn "Stage 4 prereqs issues"; fi
if command -v gh >/dev/null 2>&1; then
  gh run list --workflow security-gates.yml --limit 1 | tee -a "$SUMMARY" || true
else
  warn "gh not installed; cannot confirm security-gates via API"
fi

# Integrated health checks
log "\n-- Integrated Health Checks --"
aws eks update-kubeconfig --name "$CLUSTER" --region "$REGION" >>"$SUMMARY" 2>&1 || warn "Unable to update kubeconfig"
kubectl get nodes -o wide | tee -a "$SUMMARY" || true
kubectl -n "$NS" get pods,svc -o wide | tee -a "$SUMMARY" || true

# Backend /health
set +e
kubectl -n "$NS" port-forward deploy/backend 18080:8000 >/tmp/pf.log 2>&1 &
PF=$!
sleep 3
CODE=$(curl -sS -o /dev/null -w "%{http_code}" http://127.0.0.1:18080/health || true)
kill $PF 2>/dev/null || true
set -e
if [ "$CODE" = "200" ]; then ok "Backend /health 200"; else fail "Backend /health -> $CODE"; fi

# Postgres connectivity (ephemeral netshoot)
set +e
kubectl -n "$NS" run netcheck-final --image=nicolaka/netshoot:latest --restart=Never -- sleep 3600 >/dev/null 2>&1
kubectl -n "$NS" wait --for=condition=Ready pod/netcheck-final --timeout=60s >/dev/null 2>&1
kubectl -n "$NS" exec netcheck-final -- sh -lc "nc -z -w 5 postgres 5432" >/dev/null 2>&1
RC=$?
kubectl -n "$NS" delete pod netcheck-final --grace-period=0 --force >/dev/null 2>&1
set -e
if [ "$RC" -eq 0 ]; then ok "Postgres TCP reachable"; else fail "Postgres TCP not reachable"; fi

log "\n===== Final Validation Complete. See $SUMMARY ====="
