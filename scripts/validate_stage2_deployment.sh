#!/usr/bin/env bash
set -euo pipefail

# validate_stage2_deployment.sh
# - Waits for pods in 'staging' to be Ready (postgres, backend, frontend)
# - Verifies backend /api/ping health via temporary port-forward
# - Verifies service-level connectivity via ephemeral curl pod
# - Collects diagnostic logs on failure into logs/

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
NS=staging
LOG_DIR="${ROOT_DIR}/logs"
mkdir -p "${LOG_DIR}"
TS="$(date +%Y%m%d-%H%M%S)"

YELLOW='\033[1;33m'; GREEN='\033[0;32m'; RED='\033[0;31m'; NC='\033[0m'
info(){ echo -e "${YELLOW}➤${NC} $*"; }
ok(){ echo -e "${GREEN}OK${NC} - $*"; }
fail(){ echo -e "${RED}FAIL${NC} - $*"; }

section(){ echo -e "\n===== $* ====="; }

section "Stage 2 deployment validation"

info "Ensuring namespace '${NS}' exists..."
kubectl get ns "$NS" >/dev/null 2>&1 || { fail "Namespace ${NS} not found"; exit 1; }

info "Waiting for pods to be Ready..."
if ! kubectl wait --for=condition=Available deployment/backend -n "$NS" --timeout=180s; then
  fail "Backend not available"
fi
if ! kubectl wait --for=condition=Available deployment/frontend -n "$NS" --timeout=180s; then
  fail "Frontend not available"
fi
if ! kubectl wait --for=condition=Ready pod -l app.kubernetes.io/name=fastticket-postgres -n "$NS" --timeout=180s; then
  fail "PostgreSQL pod not Ready"
fi
ok "All core pods report Ready"

info "Snapshot of pods:"
kubectl get pods -n "$NS" -o wide | tee "${LOG_DIR}/stage2_pods_${TS}.log"

# Test backend /api/ping via port-forward
info "Testing backend /api/ping via port-forward..."
PF_PID=0
(kubectl -n "$NS" port-forward svc/backend 18080:8080 >/dev/null 2>&1 & echo $! >"${LOG_DIR}/pf_backend_${TS}.pid") || true
sleep 2
if curl -fsS http://127.0.0.1:18080/health | tee "${LOG_DIR}/stage2_backend_health_${TS}.log" | grep -q '"ok"'; then
  ok "Backend health OK"
else
  fail "Backend health check failed"
fi
# Cleanup port-forward
if [[ -f "${LOG_DIR}/pf_backend_${TS}.pid" ]]; then
  kill "$(cat "${LOG_DIR}/pf_backend_${TS}.pid")" 2>/dev/null || true
  rm -f "${LOG_DIR}/pf_backend_${TS}.pid"
fi

# Service connectivity checks using ephemeral curl pod
info "Validating service connectivity via ephemeral pod..."
set +e
kubectl -n "$NS" delete pod netcheck --ignore-not-found
kubectl -n "$NS" run netcheck --image=curlimages/curl:8.10.1 --restart=Never --command -- sleep 3600 >/dev/null 2>&1
kubectl -n "$NS" wait --for=condition=Ready pod/netcheck --timeout=60s >/dev/null 2>&1

# backend from netcheck
kubectl -n "$NS" exec netcheck -- sh -c "curl -fsS http://backend:8080/health" | tee "${LOG_DIR}/stage2_net_backend_${TS}.log"
RC1=$?
# postgres TCP connectivity (expect no HTTP; just test port is open)
kubectl -n "$NS" exec netcheck -- sh -c "sh -c 'timeout 5 bash -lc </dev/tcp/postgres/5432'" >/dev/null 2>&1
RC2=$?
# frontend static index
kubectl -n "$NS" exec netcheck -- sh -c "curl -fsS http://frontend:3000/ | head -n 1" | tee "${LOG_DIR}/stage2_net_frontend_${TS}.log"
RC3=$?

kubectl -n "$NS" delete pod netcheck --grace-period=0 --force >/dev/null 2>&1
set -e

if (( RC1 == 0 )) && (( RC2 == 0 )) && (( RC3 == 0 )); then
  ok "Service connectivity checks passed"
else
  fail "Service connectivity checks failed (backend:${RC1} postgres:${RC2} frontend:${RC3})"
  echo "Collecting diagnostics..."
  kubectl -n "$NS" describe pods > "${LOG_DIR}/stage2_pod_describe_${TS}.log" || true
  kubectl -n "$NS" logs --all-containers=true --prefix > "${LOG_DIR}/stage2_pod_logs_${TS}.log" || true
  kubectl get events -n "$NS" --sort-by=.lastTimestamp > "${LOG_DIR}/stage2_events_${TS}.log" || true
  exit 3
fi

echo
ok "Stage 2 validation: OK"
