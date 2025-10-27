#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

mkdir -p logs

get_owner_repo() {
  local url
  url=$(git config --get remote.origin.url || echo "")
  if [[ "$url" =~ github.com[:/](.+/.+?)(\.git)?$ ]]; then
    echo "${BASH_REMATCH[1]}"
  else
    echo "<owner/repo>"
  fi
}

OWNER_REPO=$(get_owner_repo)
CI_URL="https://github.com/${OWNER_REPO}/actions/workflows/ci.yml"
CD_URL="https://github.com/${OWNER_REPO}/actions/workflows/cd-staging.yml"

echo "CI workflow: $CI_URL"
echo "CD workflow: $CD_URL"

if command -v gh >/dev/null 2>&1; then
  echo "== Checking latest CI status on current branch =="
  gh run list --workflow ci.yml --limit 1 || true
  echo "== Checking latest CD (main) status =="
  gh run list --workflow cd-staging.yml --limit 1 || true
else
  echo "[INFO] 'gh' not installed; open the URLs above to view run history."
fi

# Optional: basic cluster health and log collection
NS="staging"
echo "\n== Collecting cluster diagnostics =="
set +e
kubectl -n "$NS" get pods -o wide > logs/stage3_pods.log 2>&1
kubectl -n "$NS" describe pods > logs/stage3_describe.log 2>&1
kubectl -n "$NS" logs --all-containers=true --prefix=true > logs/stage3_logs.log 2>&1
kubectl -n "$NS" get events --sort-by=.lastTimestamp > logs/stage3_events.log 2>&1
set -e

echo "Saved diagnostics under logs/"

# Determine health by checking /health
HEALTH_CODE=000
set +e
kubectl -n "$NS" port-forward deploy/backend 18080:8000 >/tmp/pf.log 2>&1 &
PF=$!
sleep 3
HEALTH_CODE=$(curl -sS -o /dev/null -w "%{http_code}" http://127.0.0.1:18080/health || true)
kill $PF 2>/dev/null || true
set -e

echo "Backend /health HTTP status: $HEALTH_CODE"

if [ "$HEALTH_CODE" != "200" ]; then
  echo "\n[ERROR] Deployment seems unhealthy. Generating issue report..."
  REPORT="logs/stage3_issue_report.txt"
  {
    echo "Workflow URLs:"
    echo "- CI: $CI_URL"
    echo "- CD: $CD_URL"
    echo
    echo "Backend /health status: $HEALTH_CODE"
    echo
    echo "Suspected categories:"
    echo "- Deployment Error or Runtime Error"
    echo
    echo "Action Plan:"
    echo "1) Inspect CI logs for build/test failures"
    echo "2) Verify credentials/secrets for CD (DockerHub, AWS role)"
    echo "3) Inspect cluster logs (see logs/ files)"
    echo "4) Isolate root cause (image, permissions, k8s config)"
    echo "5) Patch workflow/manifests, re-run pipeline"
  } > "$REPORT"
  echo "Wrote $REPORT"
  exit 1
else
  echo "\n[OK] Stage 3 pipeline health check passed locally."
fi
