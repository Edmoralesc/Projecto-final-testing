#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
NS="staging"
SVC_FILE="${ROOT_DIR}/k8s/public/services.yaml"

ok(){ echo -e "[OK] $*"; }
warn(){ echo -e "[WARN] $*"; }
fail(){ echo -e "[FAIL] $*"; exit 1; }

echo "== Public Exposure Prerequisites =="

# Tools
for c in kubectl aws jq; do
  if command -v "$c" >/dev/null 2>&1; then ok "$c present"; else warn "$c not found"; fi
done

# Kube access
if kubectl version --client >/dev/null 2>&1 && kubectl get ns "$NS" >/dev/null 2>&1; then
  ok "Kube access and namespace '$NS' present"
else
  fail "Cannot access cluster or namespace '$NS' is missing"
fi

# Manifests
if [[ -f "$SVC_FILE" ]]; then ok "Found $SVC_FILE"; else fail "Missing $SVC_FILE"; fi

cat <<EOF

Notes:
- This will create two AWS ELB (classic) load balancers (backend-public, frontend-public) in region configured in your kube context's cluster.
- ELB incurs hourly and data-transfer charges. Use cleanup script to delete when finished.

EOF

echo "RESULT: PASS"
