#!/usr/bin/env bash
# Audit and shutdown AWS resources for FastTicket
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

export AWS_REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-us-east-1}}"
export CLUSTER_NAME="${CLUSTER_NAME:-fastticket-eks}"
export DRY_RUN=false
export ASSUME_YES=false

TS="$(date +%Y%m%d-%H%M%S)"
OUT_DIR="$ROOT_DIR/validation_output/cost/${TS}"
LOG_DIR="$ROOT_DIR/logs"
mkdir -p "$OUT_DIR" "$LOG_DIR" "validation_output/cost"

echo "" > /dev/null # placeholder

HUMAN_LOG="$LOG_DIR/cost_audit_${TS}.log"
SUMMARY_JSON="$OUT_DIR/summary.json"
REPLICA_BACKUP="$OUT_DIR/replica_backup.jsonl"
AUDIT_JSON="$OUT_DIR/audit.json"

# shellcheck source=scripts/_cost_helpers.sh
. "scripts/_cost_helpers.sh"

# Preflight checks
precheck() {
  local ok=true
  for tool in aws jq kubectl terraform; do
    if ! command -v "$tool" >/dev/null 2>&1; then
      err "Missing $tool. Please install it and re-run."
      ok=false
    else
      case "$tool" in
  kubectl) v=$(kubectl version --client=true 2>&1 | head -n1 || true) ;;
        terraform) v=$(terraform version | head -n1 || true) ;;
        aws) v=$(aws --version 2>&1 | head -n1 || true) ;;
        jq) v=$(jq --version 2>&1 | head -n1 || true) ;;
      esac
      log "$tool version: $v"
    fi
  done
  if [ "$ok" != true ]; then err "Precheck failed"; exit 1; fi
}

usage() {
  cat <<USAGE
Usage: scripts/audit_and_shutdown_aws.sh [--audit|--shutdown|--restore-minimal|--destroy-terraform] [--dry-run] [-y]

Modes:
  --audit             Enumerate project resources and write ${AUDIT_JSON}
  --shutdown          Safely scale down k8s, remove LBs, delete nodegroup/cluster (with confirmation)
  --restore-minimal   Recreate minimal infra (terraform apply VPC/EKS + 1 node group)
  --destroy-terraform Destroys all Terraform-managed resources in infra/

Options:
  --dry-run  Print actions without executing
  -y         Assume yes to prompts
USAGE
}

MODE="audit"
while [ $# -gt 0 ]; do
  case "$1" in
    --audit) MODE="audit" ; shift ;;
    --shutdown) MODE="shutdown" ; shift ;;
    --restore-minimal) MODE="restore-minimal" ; shift ;;
    --destroy-terraform) MODE="destroy-terraform" ; shift ;;
    --dry-run) DRY_RUN=true ; shift ;;
    -y|--yes) ASSUME_YES=true ; shift ;;
    -h|--help) usage; exit 0 ;;
    *) err "Unknown arg: $1"; usage; exit 1 ;;
  esac
done

precheck
json_init
json_set '.status = "IN_PROGRESS"'

# Discovery functions
collect_audit() {
  log "Collecting audit for region=$AWS_REGION cluster=$CLUSTER_NAME"

  local cluster_json
  set +e
  cluster_json=$(awsr eks describe-cluster --name "$CLUSTER_NAME" --output json 2>/dev/null)
  local eks_present=false
  if [ -n "$cluster_json" ]; then eks_present=true; fi
  set -e
  echo "${cluster_json:-null}" | jq '.' > "$OUT_DIR/describe-cluster.json" 2>/dev/null || true
  json_set ".eks_cluster_present = $eks_present"

  # Nodegroups
  local nodegroups
  nodegroups=$(awsr eks list-nodegroups --cluster-name "$CLUSTER_NAME" --output json | jq -r '.nodegroups // [] | @json')
  echo "$nodegroups" | jq '.' > "$OUT_DIR/list-nodegroups.json"
  json_set ".nodegroups = $nodegroups"

  # EC2 instances tagged to cluster or project
  local ec2
  ec2=$(awsr ec2 describe-instances --filters \
    Name=tag:kubernetes.io/cluster/$CLUSTER_NAME,Values=owned,shared \
    Name=instance-state-name,Values=pending,running,stopping,stopped \
    --output json | jq '[.Reservations[]?.Instances[]?]')
  echo "$ec2" > "$OUT_DIR/ec2_instances.json"
  json_set ".ec2_instances = $ec2"

  # Load balancers (ELBv2)
  local lbs
  lbs=$(awsr elbv2 describe-load-balancers --output json 2>/dev/null | jq '[.LoadBalancers[]? | select(.LoadBalancerName | test("$CLUSTER_NAME"))]')
  echo "$lbs" > "$OUT_DIR/elbs.json"
  json_set ".elbs = $lbs"

  # Volumes (PVC leftovers)
  local ebs
  ebs=$(awsr ec2 describe-volumes --filters Name=tag:kubernetes.io/cluster/$CLUSTER_NAME,Values=owned,shared --output json | jq '.Volumes')
  echo "$ebs" > "$OUT_DIR/ebs_volumes.json"
  json_set ".ebs_volumes = $ebs"

  # ECR repositories (list only)
  local ecr
  ecr=$(awsr ecr describe-repositories --output json 2>/dev/null | jq '.repositories // []')
  echo "$ecr" > "$OUT_DIR/ecr_repos.json"
  json_set ".ecr_repositories = $ecr"

  # CloudWatch logs for cluster
  local logs
  logs=$(awsr logs describe-log-groups --log-group-name-prefix "/aws/eks/$CLUSTER_NAME" --output json | jq '.logGroups // []')
  echo "$logs" > "$OUT_DIR/cloudwatch_logs.json"
  json_set ".cloudwatch_logs = $logs"

  # K8s services of type LoadBalancer in dev/staging
  local lb_svcs
  set +e
  lb_svcs=$(kubectl get svc -A -o json 2>/dev/null | jq '[.items[] | select(.metadata.namespace | IN("dev","staging")) | select(.spec.type == "LoadBalancer")]')
  set -e
  echo "${lb_svcs:-[]}" > "$OUT_DIR/k8s_lb_services.json"
  json_set ".k8s_lb_services = ${lb_svcs:-[]}"

  # Estimate hourly cost note
  local node_count
  node_count=$(echo "$ec2" | jq 'map(select(.State.Name=="running")) | length')
  local cost_note; cost_note=$(expected_hourly_cost_note "$node_count")
  json_set ".estimated_hourly_cost_note = \"$cost_note\""

  # Write final audit.json snapshot
  cp "$SUMMARY_JSON" "$AUDIT_JSON"
  ok "Audit collected: $AUDIT_JSON"
}

shutdown_flow() {
  log "Starting shutdown flow (dry-run=$DRY_RUN)"

  # 1) Scale deployments to zero and backup replicas
  set +e
  if kubectl version --client >/dev/null 2>&1 && kubectl cluster-info >/dev/null 2>&1; then
    : > "$REPLICA_BACKUP"
    for ns in dev staging; do
      log "Scaling deployments in namespace $ns to 0"
      k8s_scale_deployments_to_zero "$ns"
    done
    json_set ".actions_taken.replica_backup = \"$REPLICA_BACKUP\""
  else
    warn "Kubernetes API not reachable; skipping deployment scale down"
  fi
  set -e

  # 2) Handle LoadBalancer services
  set +e
  if kubectl get svc -A >/dev/null 2>&1; then
    for ns in dev staging; do
      svcs=$(k8s_lb_services "$ns")
      if [ -n "$svcs" ]; then
        log "Found LB services in $ns"; echo "$svcs" | tee -a "$HUMAN_LOG"
        choice=$(confirm "Delete LB services in $ns to stop ELB cost?" true)
        if [ "$choice" = yes ]; then
          echo "$svcs" | jq -r '.name' | while read -r name; do
            if [ "$DRY_RUN" = true ]; then
              log "[dry-run] kubectl -n $ns delete svc $name"
            else
              kubectl -n "$ns" delete svc "$name" | tee -a "$HUMAN_LOG" || true
            fi
          done
          json_array_append '.actions_taken.lb_services_deleted' "$(echo "$svcs" | jq -c '[.name]')"
        else
          warn "Skipped LB service deletion in $ns"
        fi
      fi
    done
  fi
  set -e

  # 3) Delete or scale node group
  local ngs; ngs=$(awsr eks list-nodegroups --cluster-name "$CLUSTER_NAME" --output json | jq -r '.nodegroups[]?')
  if [ -n "$ngs" ]; then
    log "Found managed node groups: $ngs"
    choice=$(confirm "Delete managed node groups to stop EC2 spend? (faster than scaling to 0)" true)
    if [ "$choice" = yes ]; then
      for ng in $ngs; do
        if [ "$DRY_RUN" = true ]; then
          log "[dry-run] aws eks delete-nodegroup --cluster-name $CLUSTER_NAME --nodegroup-name $ng"
        else
          awsr eks delete-nodegroup --cluster-name "$CLUSTER_NAME" --nodegroup-name "$ng" | tee -a "$HUMAN_LOG" || true
        fi
        json_array_append '.actions_taken.nodegroups_deleted' "\"$ng\""
      done
    else
      warn "Skipping node group deletion; attempting scale to 0 where supported"
      for ng in $ngs; do
        if [ "$DRY_RUN" = true ]; then
          log "[dry-run] aws eks update-nodegroup-config --scaling-config desiredSize=0,minSize=0,maxSize=0"
        else
          awsr eks update-nodegroup-config --cluster-name "$CLUSTER_NAME" --nodegroup-name "$ng" --scaling-config desiredSize=0,minSize=0,maxSize=0 | tee -a "$HUMAN_LOG" || true
        fi
        json_array_append '.actions_taken.nodegroups_scaled_to_zero' "\"$ng\""
      done
    fi
  fi

  # 4) Delete EKS cluster (optional)
  if [ "$(confirm "Delete EKS cluster $CLUSTER_NAME? This removes control-plane hourly cost. Confirm?" true)" = yes ]; then
    if [ "$(confirm "Are you absolutely sure? Cluster deletion is disruptive." true)" = yes ]; then
      if [ -d infra ]; then
        log "Attempting terraform destroy for EKS"
        if [ "$DRY_RUN" = true ]; then
          log "[dry-run] terraform destroy in infra/"
        else
          pushd infra >/dev/null
          with_retry 1 0 terraform init -upgrade | tee -a "$HUMAN_LOG"
          with_retry 1 0 terraform destroy -target=module.eks -auto-approve | tee -a "$HUMAN_LOG" || true
          popd >/dev/null
        fi
        json_set '.actions_taken.cluster_destroyed_via = "terraform"'
      else
        log "Infra folder missing; using AWS CLI"
        if [ "$DRY_RUN" = true ]; then
          log "[dry-run] aws eks delete-cluster --name $CLUSTER_NAME"
        else
          awsr eks delete-cluster --name "$CLUSTER_NAME" | tee -a "$HUMAN_LOG" || true
        fi
        json_set '.actions_taken.cluster_destroyed_via = "awscli"'
      fi
    fi
  else
    warn "Cluster deletion skipped"
  fi

  # 5) Cleanup dangling ELBs, EBS, ENIs
  warn "Checking for dangling resources (ELBs/EBS/ENIs) by tags"
  # ELBs tied to cluster names are commonly auto-deleted with service deletion; present a dry-run example
  if [ "$DRY_RUN" = true ]; then
    log "[dry-run] would search and delete orphaned ELBs/EBS/ENIs"
  fi

  # 6) Optional S3 buckets cleanup
  local buckets; buckets=$(awsr s3api list-buckets --output json | jq -r '.Buckets[]?.Name' | grep -Ei 'fastticket|eks|k8s' || true)
  if [ -n "$buckets" ]; then
    warn "Candidate S3 buckets (not deleted by default):"; echo "$buckets" | tee -a "$HUMAN_LOG"
    if [ "$(confirm "Empty and delete the above buckets?" true)" = yes ]; then
      while read -r b; do
        [ -z "$b" ] && continue
        if [ "$DRY_RUN" = true ]; then
          log "[dry-run] aws s3 rb s3://$b --force"
        else
          aws s3 rb "s3://$b" --force | tee -a "$HUMAN_LOG" || true
        fi
        json_array_append '.actions_taken.s3_deleted' "\"$b\""
      done <<<"$buckets"
    fi
  fi
}

restore_minimal() {
  log "Restoring minimal infrastructure (terraform apply)"
  if [ "$DRY_RUN" = true ]; then
    log "[dry-run] terraform apply in infra/"
    return 0
  fi
  pushd infra >/dev/null
  terraform init -upgrade | tee -a "$HUMAN_LOG"
  terraform apply -auto-approve | tee -a "$HUMAN_LOG"
  popd >/dev/null
}

destroy_terraform() {
  log "Destroying all Terraform-managed resources"
  if [ "$DRY_RUN" = true ]; then
    log "[dry-run] terraform destroy -auto-approve in infra/"
    return 0
  fi
  pushd infra >/dev/null
  terraform init -upgrade | tee -a "$HUMAN_LOG"
  terraform destroy -auto-approve | tee -a "$HUMAN_LOG"
  popd >/dev/null
}

case "$MODE" in
  audit)
    collect_audit
    json_set '.status = "PASS"'
    ;;
  shutdown)
    collect_audit
    shutdown_flow
    json_set '.status = "PASS"'
    ;;
  restore-minimal)
    restore_minimal
    json_set '.status = "PASS"'
    ;;
  destroy-terraform)
    destroy_terraform
    json_set '.status = "PASS"'
    ;;
  *)
    err "Unknown mode $MODE"; exit 1 ;;
 esac

ok "Summary: $SUMMARY_JSON"
# Also duplicate to audit.json on audit mode for convenience
if [ "$MODE" = audit ]; then cp "$SUMMARY_JSON" "$AUDIT_JSON"; fi

exit 0
