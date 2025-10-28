#!/usr/bin/env bash
# Usage: scripts/validate_stage1_infra.sh [--cluster fastticket-eks]
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

TS="$(date +%Y%m%d-%H%M%S)"
OUT_BASE="$ROOT_DIR/validation_output/stage1/${TS}"
LOG_DIR="$ROOT_DIR/logs"
mkdir -p "$OUT_BASE" "$LOG_DIR"

REGION="us-east-1"
CLUSTER="fastticket-eks"
if [ "${1:-}" = "--cluster" ] && [ -n "${2:-}" ]; then
  CLUSTER="$2"
fi

# state vars
terraform_init=false
terraform_validate=false
terraform_plan=false
eks_cluster_active=false
nodegroup_active=false
kube_api_ok=false
nodes_ready_count=0
kube_system_ok=false
scaled_coredns_to_1=false

# terraform checks
{
  echo "== Terraform init/validate/plan =="
  pushd infra >/dev/null
  terraform init -upgrade | tee "$OUT_BASE/terraform_init.txt"
  terraform_init=true
  terraform validate | tee "$OUT_BASE/terraform_validate.txt"
  terraform_validate=true
  terraform plan -lock=false -out=plan.out | tee "$OUT_BASE/terraform_plan.txt"
  terraform show -no-color plan.out > "$OUT_BASE/plan.txt" || true
  cp plan.out "$OUT_BASE/plan.out"
  terraform_plan=true
  popd >/dev/null
} || true

# EKS describe
set +e
aws eks describe-cluster --name "$CLUSTER" --region "$REGION" --output json > "$OUT_BASE/describe-cluster.json" 2>"$OUT_BASE/describe-cluster.err"
DC_RC=$?
if [ $DC_RC -eq 0 ]; then
  status=$(jq -r '.cluster.status' "$OUT_BASE/describe-cluster.json" 2>/dev/null)
  [ "$status" = "ACTIVE" ] && eks_cluster_active=true
fi

aws eks list-nodegroups --cluster-name "$CLUSTER" --region "$REGION" --output json > "$OUT_BASE/list-nodegroups.json" 2>"$OUT_BASE/list-nodegroups.err"
NG_RC=$?
if [ $NG_RC -eq 0 ]; then
  ng=$(jq -r '.nodegroups[]?|select(test("^ng-main"))' "$OUT_BASE/list-nodegroups.json" 2>/dev/null | head -n1)
  if [ -n "$ng" ]; then
    aws eks describe-nodegroup --cluster-name "$CLUSTER" --nodegroup-name "$ng" --region "$REGION" --output json > "$OUT_BASE/describe-nodegroup.json" 2>"$OUT_BASE/describe-nodegroup.err"
    if [ $? -eq 0 ]; then
      ng_status=$(jq -r '.nodegroup.status' "$OUT_BASE/describe-nodegroup.json" 2>/dev/null)
      [ "$ng_status" = "ACTIVE" ] && nodegroup_active=true
    fi
  fi
fi

# kubeconfig and cluster-info
aws eks update-kubeconfig --name "$CLUSTER" --region "$REGION" >>"$OUT_BASE/kubeconfig.txt" 2>&1
kubectl cluster-info > "$OUT_BASE/cluster-info.txt" 2>&1
[ $? -eq 0 ] && kube_api_ok=true

kubectl get nodes -o wide > "$OUT_BASE/nodes.txt" 2>&1
nodes_ready_count=$(kubectl get nodes --no-headers 2>/dev/null | awk '$2 ~ /Ready/ {c++} END{print c+0}')

kubectl -n kube-system get pods > "$OUT_BASE/kube-system-pods.txt" 2>&1
not_ready=$(awk 'NR>1 && $2 !~ /1\/1|2\/2/ {c++} END{print c+0}' "$OUT_BASE/kube-system-pods.txt")
[ "${not_ready:-0}" -eq 0 ] && kube_system_ok=true

# Optional coredns downscale if tiny cluster
node_count=$(kubectl get nodes -o json 2>/dev/null | jq '.items|length' 2>/dev/null || echo 0)
if [ "$node_count" = "1" ]; then
  # memory in Ki -> Mi
  memKi=$(kubectl get nodes -o json | jq -r '.items[0].status.capacity.memory' 2>/dev/null | tr -d 'Ki')
  if [ -n "$memKi" ]; then
    memMi=$(( memKi / 1024 ))
    if [ "$memMi" -lt 2048 ]; then
      # ensure coredns > 1 then scale to 1
      cd_replicas=$(kubectl -n kube-system get deploy/coredns -o jsonpath='{.spec.replicas}' 2>/dev/null || echo 2)
      if [ "${cd_replicas:-2}" -gt 1 ]; then
        kubectl -n kube-system scale deploy/coredns --replicas=1 >>"$OUT_BASE/coredns-scale.txt" 2>&1 || true
        scaled_coredns_to_1=true
      fi
    fi
  fi
fi

# Diagnostics (always best effort)
kubectl get events -A --sort-by=.lastTimestamp > "$LOG_DIR/stage1_events.log" 2>&1 || true
kubectl -n kube-system describe pods > "$LOG_DIR/stage1_kube_system_describe.log" 2>&1 || true
{
  for p in $(kubectl -n kube-system get pods -o name 2>/dev/null); do
    echo "==== $p ===="
    kubectl -n kube-system logs --all-containers=true --prefix=true "$p" || true
  done
} > "$LOG_DIR/stage1_kube_system_logs.log" 2>&1 || true
set -e

status="PASS"
if [ "$terraform_init" != true ] || [ "$terraform_validate" != true ] || [ "$terraform_plan" != true ] || [ "$eks_cluster_active" != true ] || [ "$nodegroup_active" != true ] || [ "$kube_api_ok" != true ]; then
  status="FAIL"
fi

cat > "$OUT_BASE/summary.json" <<JSON
{
  "terraform_init": $terraform_init,
  "terraform_validate": $terraform_validate,
  "terraform_plan": $terraform_plan,
  "eks_cluster_active": $eks_cluster_active,
  "nodegroup_active": $nodegroup_active,
  "kube_api_ok": $kube_api_ok,
  "nodes_ready_count": $nodes_ready_count,
  "kube_system_ok": $kube_system_ok,
  "actions": { "scaled_coredns_to_1": $scaled_coredns_to_1 },
  "status": "${status}"
}
JSON

echo "Stage1 Infra: terraform_init=${terraform_init} terraform_validate=${terraform_validate} terraform_plan=${terraform_plan} eks_cluster_active=${eks_cluster_active} nodegroup_active=${nodegroup_active} kube_api_ok=${kube_api_ok} status=${status}"
[ "$status" = "PASS" ] || exit 2
