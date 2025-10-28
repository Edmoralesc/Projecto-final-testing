#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

NS="staging"
OWNER_REPO=$(git config --get remote.origin.url | sed -E 's#.*/([^/]+/[^/]+)(\.git)?$#\1#')
[ -z "$OWNER_REPO" ] && OWNER_REPO="<owner/repo>"
URL="https://github.com/${OWNER_REPO}/actions/workflows/security-gates.yml"

echo "Security Gates workflow: $URL"
if command -v gh >/dev/null 2>&1; then
  echo "== Latest security-gates runs =="
  gh run list --workflow security-gates.yml --limit 3 || true
else
  echo "[INFO] 'gh' not installed; open the URL above to check runs."
fi

echo "\n== Collecting cluster diagnostics (if needed) =="
mkdir -p logs
set +e
kubectl -n "$NS" get pods -o wide > logs/stage4_pods.log 2>&1
kubectl -n "$NS" describe pods > logs/stage4_describe.log 2>&1
kubectl -n "$NS" logs --all-containers=true --prefix=true > logs/stage4_logs.log 2>&1
kubectl -n "$NS" get events --sort-by=.lastTimestamp > logs/stage4_events.log 2>&1
set -e

echo "Saved logs under logs/"

echo "\nPASS/FAIL is determined by the 'gates' job in the workflow. Review 'security-gates-summary' artifact for details."
