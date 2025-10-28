#!/bin/bash
# eks_nodegroup_diagnose.sh
# Enhanced diagnostic + self-healing IAM policy verification for EKS Node Groups

set -euo pipefail

# ---------- CONFIGURATION (overridable via flags) ----------
CLUSTER="fastticket-eks"
NODEGROUP=""           # If empty, will auto-detect from cluster
REGION="us-east-1"
AUTO_FIX_IAM=true     # set to false if you want only validation, no automatic fixes

usage() {
  echo "Usage: $0 [-c CLUSTER] [-n NODEGROUP] [-r REGION] [--no-fix]";
  exit 1;
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -c|--cluster) CLUSTER="$2"; shift 2;;
    -n|--nodegroup) NODEGROUP="$2"; shift 2;;
    -r|--region) REGION="$2"; shift 2;;
    --no-fix) AUTO_FIX_IAM=false; shift;;
    -h|--help) usage;;
    *) echo "Unknown arg: $1"; usage;;
  esac
done

# ---------- INITIAL SETUP ----------
TS=$(date +"%Y%m%d-%H%M%S")
LOGFILE="eks_nodegroup_diagnostics_${CLUSTER}_${TS}.log"

if [[ -z "$NODEGROUP" ]]; then
  # Try to pick the first non-ACTIVE nodegroup, else the newest one
  echo "Auto-detecting nodegroup for cluster $CLUSTER..." | tee -a "$LOGFILE"
  CANDIDATES=$(aws eks list-nodegroups --cluster-name "$CLUSTER" --region "$REGION" --query 'nodegroups[]' --output text || true)
  if [[ -n "$CANDIDATES" ]]; then
    for NG in $CANDIDATES; do
      STATUS=$(aws eks describe-nodegroup --cluster-name "$CLUSTER" --nodegroup-name "$NG" --region "$REGION" --query 'nodegroup.status' --output text || echo "unknown")
      if [[ "$STATUS" != "ACTIVE" ]]; then NODEGROUP="$NG"; break; fi
    done
    if [[ -z "$NODEGROUP" ]]; then NODEGROUP=$(echo "$CANDIDATES" | head -n1); fi
  fi
fi

echo "EKS Node Group Diagnostics - $CLUSTER / ${NODEGROUP:-<none>}" | tee "$LOGFILE"
echo "Region: $REGION" | tee -a "$LOGFILE"
echo "Timestamp: $TS" | tee -a "$LOGFILE"
echo "=================================================" | tee -a "$LOGFILE"

# ---------- 1. EKS NODEGROUP STATUS ----------
echo -e "\n[1] NodeGroup Status & Health" | tee -a "$LOGFILE"
if [[ -n "$NODEGROUP" ]]; then
  aws eks describe-nodegroup \
    --cluster-name "$CLUSTER" \
    --nodegroup-name "$NODEGROUP" \
    --region "$REGION" \
    --output json | tee -a "$LOGFILE"
else
  echo "No nodegroup found for diagnostics." | tee -a "$LOGFILE"
fi

# ---------- 2. NODEGROUP HEALTH & INSTANCE IDS ----------
INSTANCE_IDS=""
if [[ -n "$NODEGROUP" ]]; then
  INSTANCE_IDS=$(aws eks describe-nodegroup \
    --cluster-name "$CLUSTER" \
    --nodegroup-name "$NODEGROUP" \
    --region "$REGION" \
    --query "nodegroup.health.issues[].resourceIds[]" \
    --output text || true)
fi

echo -e "\n[2] Affected Instance IDs: ${INSTANCE_IDS:-None found}" | tee -a "$LOGFILE"

# ---------- 3. AUTO SCALING GROUP INFO ----------
ASG=""
if [[ -n "$NODEGROUP" ]]; then
  ASG=$(aws autoscaling describe-auto-scaling-groups \
    --region "$REGION" \
    --query "AutoScalingGroups[?contains(Tags[?Key=='eks:nodegroup-name'].Value, '$NODEGROUP')].AutoScalingGroupName | [0]" \
    --output text || true)
fi

echo -e "\n[3] Auto Scaling Group: $ASG" | tee -a "$LOGFILE"
if [[ -n "$ASG" && "$ASG" != "None" ]]; then
  aws autoscaling describe-auto-scaling-groups \
    --auto-scaling-group-names "$ASG" \
    --region "$REGION" \
    --output json | tee -a "$LOGFILE"
else
  echo "No ASG found for nodegroup." | tee -a "$LOGFILE"
fi

# ---------- 4. AUTO SCALING ACTIVITY LOGS ----------
echo -e "\n[4] Auto Scaling Activity Logs" | tee -a "$LOGFILE"
if [[ -n "$ASG" && "$ASG" != "None" ]]; then
  aws autoscaling describe-scaling-activities \
    --region "$REGION" \
    --auto-scaling-group-name "$ASG" \
    --max-items 15 \
    --output table | tee -a "$LOGFILE"
else
  echo "No scaling activities; ASG not found." | tee -a "$LOGFILE"
fi

# ---------- 5. EC2 INSTANCE DETAILS ----------
echo -e "\n[5] EC2 Instance Details" | tee -a "$LOGFILE"
if [ -n "$INSTANCE_IDS" ]; then
  aws ec2 describe-instances \
    --instance-ids $INSTANCE_IDS \
    --region "$REGION" \
    --query "Reservations[].Instances[].{ID:InstanceId,State:State.Name,AZ:Placement.AvailabilityZone,Type:InstanceType,PrivIP:PrivateIpAddress,LaunchTime:LaunchTime}" \
    --output table | tee -a "$LOGFILE"
else
  echo "No instance IDs found." | tee -a "$LOGFILE"
fi

# ---------- 6. IAM ROLE CHECK + FIX ----------
echo -e "\n[6] Node IAM Role Validation & Auto-Fix" | tee -a "$LOGFILE"

NODE_ROLE_ARN=""
NODE_ROLE_NAME=""
if [[ -n "$NODEGROUP" ]]; then
  NODE_ROLE_ARN=$(aws eks describe-nodegroup \
    --cluster-name "$CLUSTER" \
    --nodegroup-name "$NODEGROUP" \
    --region "$REGION" \
    --query "nodegroup.nodeRole" \
    --output text || true)
  NODE_ROLE_NAME=${NODE_ROLE_ARN##*/}
fi

echo "Detected Node Role: $NODE_ROLE_NAME" | tee -a "$LOGFILE"

REQUIRED_POLICIES=(
  "AmazonEKSWorkerNodePolicy"
  "AmazonEKS_CNI_Policy"
  "AmazonEC2ContainerRegistryReadOnly"
)

ATTACHED_POLICIES=""
if [[ -n "$NODE_ROLE_NAME" && "$NODE_ROLE_NAME" != "None" ]]; then
  ATTACHED_POLICIES=$(aws iam list-attached-role-policies \
    --role-name "$NODE_ROLE_NAME" \
    --region "$REGION" \
    --query "AttachedPolicies[].PolicyName" \
    --output text || true)
fi

echo -e "\nAttached Policies:\n$ATTACHED_POLICIES\n" | tee -a "$LOGFILE"

if [[ -n "$NODE_ROLE_NAME" && "$NODE_ROLE_NAME" != "None" ]]; then
  for POLICY in "${REQUIRED_POLICIES[@]}"; do
    if echo "$ATTACHED_POLICIES" | grep -q "$POLICY"; then
      echo "✅ $POLICY is attached." | tee -a "$LOGFILE"
    else
      echo "❌ $POLICY is missing!" | tee -a "$LOGFILE"
      if [ "$AUTO_FIX_IAM" = true ]; then
        POLICY_ARN="arn:aws:iam::aws:policy/$POLICY"
        echo "→ Attaching $POLICY to $NODE_ROLE_NAME ..." | tee -a "$LOGFILE"
        aws iam attach-role-policy \
          --role-name "$NODE_ROLE_NAME" \
          --policy-arn "$POLICY_ARN" || true
      fi
    fi
  done
else
  echo "Skipping IAM role checks; no node role found yet." | tee -a "$LOGFILE"
fi

# ---------- 7. NETWORKING / SUBNET ROUTES ----------
echo -e "\n[7] Subnet Routing Checks" | tee -a "$LOGFILE"
SUBNETS=""
if [[ -n "$NODEGROUP" ]]; then
  SUBNETS=$(aws eks describe-nodegroup \
    --cluster-name "$CLUSTER" \
    --nodegroup-name "$NODEGROUP" \
    --region "$REGION" \
    --query "nodegroup.subnets[]" \
    --output text || true)
fi

for SUBNET in $SUBNETS; do
  echo -e "\n--- Routes for Subnet: $SUBNET ---" | tee -a "$LOGFILE"
  aws ec2 describe-route-tables \
    --region "$REGION" \
    --filters Name=association.subnet-id,Values="$SUBNET" \
    --query "RouteTables[].Routes[]" \
    --output table | tee -a "$LOGFILE"
done

# ---------- 8. CLUSTER ENDPOINT CONFIG ----------
echo -e "\n[8] Cluster Endpoint Access" | tee -a "$LOGFILE"
aws eks describe-cluster \
  --name "$CLUSTER" \
  --region "$REGION" \
  --query "cluster.resourcesVpcConfig" \
  --output json | tee -a "$LOGFILE"

# ---------- 9. METADATA OPTIONS (IMDS CHECK) ----------
echo -e "\n[9] Launch Template Metadata Options" | tee -a "$LOGFILE"
if [[ -n "$NODEGROUP" ]]; then
  LT_ID=$(aws eks describe-nodegroup \
    --cluster-name "$CLUSTER" \
    --nodegroup-name "$NODEGROUP" \
    --region "$REGION" \
    --query "nodegroup.launchTemplate.id" \
    --output text || true)

  LT_VER=$(aws eks describe-nodegroup \
    --cluster-name "$CLUSTER" \
    --nodegroup-name "$NODEGROUP" \
    --region "$REGION" \
    --query "nodegroup.launchTemplate.version" \
    --output text || true)

  if [[ -n "$LT_ID" && "$LT_ID" != "None" ]]; then
    aws ec2 describe-launch-template-versions \
      --launch-template-id "$LT_ID" \
      --versions "$LT_VER" \
      --region "$REGION" \
      --query "LaunchTemplateVersions[0].LaunchTemplateData.MetadataOptions" \
      --output json | tee -a "$LOGFILE"
  else
    echo "No launch template found yet (nodegroup still creating?)." | tee -a "$LOGFILE"
  fi
fi

# ---------- 11. EC2 Console Output for Failed Instances ----------
if [[ -n "$INSTANCE_IDS" ]]; then
  echo -e "\n[11] EC2 Console Output (last 64KB) for affected instances" | tee -a "$LOGFILE"
  for IID in $INSTANCE_IDS; do
    echo -e "\n--- Instance: $IID ---" | tee -a "$LOGFILE"
    aws ec2 get-console-output --instance-id "$IID" --region "$REGION" --output text | tail -n 200 | tee -a "$LOGFILE" || true
  done
fi

# ---------- 10. SUMMARY ----------
echo -e "\nDiagnostics complete! Log saved to: $LOGFILE"
echo -e "================================================="