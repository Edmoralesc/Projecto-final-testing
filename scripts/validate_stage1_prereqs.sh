#!/usr/bin/env bash
# Usage: scripts/validate_stage1_prereqs.sh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

TS="$(date +%Y%m%d-%H%M%S)"
OUT_DIR="validation_output/stage1/${TS}"
mkdir -p "$OUT_DIR" logs

REGION_DEFAULT="us-east-1"
CLUSTER_DEFAULT="fastticket-eks"

# Helpers
ver_ge() {
  # return 0 (true) if $1 >= $2 (semantic like 1.27.3 >= 1.27)
  # strip leading 'v'
  local a b IFS=.
  a=(${1#v}); b=(${2#v})
  local i max=${#a[@]}
  if [ ${#b[@]} -gt $max ]; then max=${#b[@]}; fi
  for ((i=0; i<max; i++)); do
    local ai=${a[i]:-0} bi=${b[i]:-0}
    if ((10#$ai > 10#$bi)); then return 0; fi
    if ((10#$ai < 10#$bi)); then return 1; fi
  done
  return 0
}

json_escape() { python - << 'PY'
import json,sys; print(json.dumps(sys.stdin.read()))
PY
}

# Version checks
terraform_ok=false
aws_ok=false
kubectl_ok=false
jq_ok=false
aws_identity=""
region="$REGION_DEFAULT"

# terraform
if command -v terraform >/dev/null 2>&1; then
  tv="$(terraform version | head -n1 | sed -E 's/.* v([0-9]+\.[0-9]+\.[0-9]+).*/\1/')"
  if ver_ge "$tv" "1.5.0"; then terraform_ok=true; fi
else
  terraform_ok=false
fi

# aws
if command -v aws >/dev/null 2>&1; then
  av="$(aws --version 2>&1 | sed -E 's#.*aws-cli/([0-9]+\.[0-9]+)\..*#\1#')"
  if ver_ge "$av" "2.0"; then aws_ok=true; fi
  # identity and region
  set +e
  aws_identity=$(aws sts get-caller-identity --output json 2>/dev/null | tr -d '\n' || true)
  # prefer env vars; fallback to default
  region="${AWS_REGION:-${AWS_DEFAULT_REGION:-$REGION_DEFAULT}}"
  set -e
else
  aws_ok=false
fi

# kubectl
if command -v kubectl >/dev/null 2>&1; then
  # try json output
  set +e
  kv_json=$(kubectl version --client -o json 2>/dev/null)
  set -e
  if [ -n "${kv_json:-}" ]; then
    kv_minor=$(echo "$kv_json" | sed -n 's/.*"minor" *: *"\([0-9][0-9]*\)".*/\1/p' | head -n1)
    kv_major=$(echo "$kv_json" | sed -n 's/.*"major" *: *"\([0-9][0-9]*\)".*/\1/p' | head -n1)
    kv="${kv_major:-1}.${kv_minor:-27}.0"
  else
    kv="$(kubectl version --client 2>&1 | sed -n 's/.*Client Version: v\([0-9.]*\).*/\1/p' | head -n1)"
  fi
  if ver_ge "$kv" "1.27.0"; then kubectl_ok=true; fi
else
  kubectl_ok=false
fi

# jq
if command -v jq >/dev/null 2>&1; then jq_ok=true; fi

# infer cluster_name from terraform.tfvars if present
cluster_name="$CLUSTER_DEFAULT"
if [ -f infra/terraform.tfvars ]; then
  # simple parse of: cluster_name = "..."
  maybe=$(sed -n 's/^\s*cluster_name\s*=\s*"\([^"]\+\)".*/\1/p' infra/terraform.tfvars | head -n1)
  if [ -n "${maybe:-}" ]; then cluster_name="$maybe"; fi
fi

# check infra folder and tf files
infra_ok=false
if [ -d infra ]; then
  if ls infra/*.tf >/dev/null 2>&1; then infra_ok=true; fi
fi

status="PASS"
if [ "$terraform_ok" != true ] || [ "$aws_ok" != true ] || [ "$kubectl_ok" != true ] || [ "$infra_ok" != true ]; then
  status="FAIL"
fi

# Write prereqs.json
cat >"$OUT_DIR/prereqs.json" <<JSON
{
  "terraform_ok": $terraform_ok,
  "aws_ok": $aws_ok,
  "kubectl_ok": $kubectl_ok,
  "jq_ok": $jq_ok,
  "infra_ok": $infra_ok,
  "aws_identity": ${aws_identity:-null},
  "region": "${region}",
  "cluster_name": "${cluster_name}",
  "status": "${status}"
}
JSON

echo "Stage1 Prereqs: terraform_ok=${terraform_ok} aws_ok=${aws_ok} kubectl_ok=${kubectl_ok} infra_ok=${infra_ok} status=${status}"

if [ "$status" != "PASS" ]; then
  echo "Prerequisites failed. See $OUT_DIR/prereqs.json"
  exit 1
fi

echo "Prerequisites PASS. Output: $OUT_DIR/prereqs.json"
