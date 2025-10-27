#!/usr/bin/env bash
# Shared helpers for cost audit/shutdown
set -euo pipefail

# Colors (optional)
if [ -t 1 ]; then
  RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; BLUE='\033[0;34m'; BOLD='\033[1m'; NC='\033[0m'
else
  RED=''; GREEN=''; YELLOW=''; BLUE=''; BOLD=''; NC=''
fi

_ts() { date +%Y%m%d-%H%M%S; }

log() { echo -e "${BOLD}[$(date -Iseconds)]${NC} $*" | tee -a "$HUMAN_LOG"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*" | tee -a "$HUMAN_LOG" >&2; }
err() { echo -e "${RED}[ERROR]${NC} $*" | tee -a "$HUMAN_LOG" >&2; }
ok() { echo -e "${GREEN}[OK]${NC} $*" | tee -a "$HUMAN_LOG"; }

confirm() {
  local prompt=${1:-"Proceed?"}
  local default_no=${2:-true}
  local ans
  if [ "${ASSUME_YES:-false}" = true ]; then
    echo "yes"
    return 0
  fi
  read -r -p "$prompt $( [ "$default_no" = true ] && echo "[y/N]" || echo "[Y/n]" ) " ans || true
  ans=${ans:-$([ "$default_no" = true ] && echo n || echo y)}
  case "$ans" in
    y|Y|yes|YES) echo "yes";;
    *) echo "no";;
  esac
}

# JSON accumulation utilities
json_init() { echo '{}' >"$SUMMARY_JSON"; }
json_set() { jq "$1" "$SUMMARY_JSON" >"$SUMMARY_JSON.tmp" && mv "$SUMMARY_JSON.tmp" "$SUMMARY_JSON"; }
json_array_append() { # $1: jq path, $2: json element string
  local path="$1"; local elem="$2"
  jq "$path += [ $elem ]" "$SUMMARY_JSON" >"$SUMMARY_JSON.tmp" && mv "$SUMMARY_JSON.tmp" "$SUMMARY_JSON";
}

with_retry() { # with_retry <max_attempts> <sleep_seconds> -- cmd args...
  local attempts=$1; shift; local sleep_s=$1; shift
  local rc=0
  for ((i=1;i<=attempts;i++)); do
    "$@" && return 0 || rc=$?
    sleep "$sleep_s"
  done
  return $rc
}

awsr() { # wrapper with retry and region
  local region="${AWS_REGION:-${AWS_DEFAULT_REGION:-us-east-1}}"
  with_retry 3 2 aws --region "$region" "$@"
}

k8s_scale_deployments_to_zero() {
  local ns="$1"
  kubectl -n "$ns" get deploy -o json | jq -c '.items[] | {name: .metadata.name, replicas: (.spec.replicas // 1)}' | while read -r item; do
    local name=$(echo "$item" | jq -r '.name'); local replicas=$(echo "$item" | jq -r '.replicas')
    echo "$replicas" | jq -n --arg n "$name" --argjson r "$replicas" '{namespace: "'$ns'", name: $n, replicas: $r}' | tee -a "$REPLICA_BACKUP" >/dev/null
    if [ "${DRY_RUN:-false}" = true ]; then
      log "[dry-run] kubectl -n $ns scale deploy/$name --replicas=0"
    else
      kubectl -n "$ns" scale deploy "$name" --replicas=0 | tee -a "$HUMAN_LOG"
    fi
  done
}

k8s_lb_services() {
  local ns="$1"
  kubectl -n "$ns" get svc -o json | jq -c '.items[] | select(.spec.type=="LoadBalancer") | {name: .metadata.name, type: .spec.type}'
}

expected_hourly_cost_note() {
  # Very rough estimates
  # EKS cluster control-plane: ~$0.10/hour
  # t3.large on-demand: ~0.0832/hour (we'll use a conservative 0.06 to 0.08 range)
  local nodes="$1"
  awk -v n="$nodes" 'BEGIN{cp=0.10; node=0.06; total=cp + n*node; printf "~$%.2f/hour", total}'
}

# Keep only N most recent logs matching pattern in a directory (e.g., prefix_*.log)
rotate_logs_keep() {
  local dir="$1"; local pattern="$2"; local keep="${3:-3}"
  # List newest first, delete anything beyond $keep
  ls -1t "$dir"/$pattern 2>/dev/null | awk -v k="$keep" 'NR>k' | while read -r f; do
    [ -n "$f" ] && rm -f "$f" || true
  done || true
}
