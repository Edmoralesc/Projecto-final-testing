#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

PASS=true

check_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "[MISSING] $1 not found in PATH"
    PASS=false
  else
    echo "[OK] $1 present: $(command -v "$1")"
  fi
}

echo "== Checking local tooling =="
check_cmd kubectl
check_cmd aws
check_cmd docker
check_cmd jq || true
check_cmd gh || true

echo "\n== Checking repo structure =="
if [ -d "k8s/overlays/staging" ]; then
  echo "[OK] k8s/overlays/staging exists"
else
  echo "[MISSING] k8s/overlays/staging not found"
  PASS=false
fi

mkdir -p reports logs

echo "\n== GitHub configuration checklist =="
REPO_URL=$(git config --get remote.origin.url || echo "<unknown>")
OWNER_REPO="$(echo "$REPO_URL" | sed -E 's#.*/([^/]+/[^/]+)(\.git)?$#\1#')"
[ -z "$OWNER_REPO" ] && OWNER_REPO="<owner/repo>"
echo "Repository: $OWNER_REPO"

cat <<EOF
Secrets (set in GitHub > Settings > Secrets and variables > Actions > Secrets):
  - DOCKERHUB_USERNAME (required)
  - DOCKERHUB_TOKEN (required)
  - AWS_ROLE_TO_ASSUME (required)  # IAM role for OIDC with EKS access

Variables (GitHub > Settings > Secrets and variables > Actions > Variables):
  - AWS_REGION = us-east-1 (recommended)

OIDC/IAM prerequisites:
  - An OIDC IAM Role for GitHub (e.g., fastticket-GitHubOIDC) trusting your org/repo with sub and aud conditions
  - Role must allow: sts:AssumeRoleWithWebIdentity and permissions to interact with EKS (cluster admin via EKS Access Entry or aws-auth mapping)

Runner tools:
  - kubectl available (GitHub ubuntu-latest includes it)
  - aws CLI available (provided by actions/ aws-actions/configure-aws-credentials)
EOF

if command -v gh >/dev/null 2>&1; then
  echo "\n== Attempting to read GH repo variables/secrets with gh (if authenticated) =="
  gh variable list || true
  gh secret list || true
else
  echo "[INFO] 'gh' not installed; skipping direct secrets/vars inspection."
fi

if [ "$PASS" = true ]; then
  echo "\nRESULT: PASS - Prerequisites look good locally. Configure GH secrets/vars if not already."
else
  echo "\nRESULT: FAIL - Please address the missing items above."
fi
