#!/bin/bash
# ============================================================
# Script: validate_eks_stage1.sh
# Author: Fernando Canales (fercanap)
# Purpose: Validation for Etapa 1 — EKS Base Infrastructure
# ============================================================

set -euo pipefail

# ========= CONFIG =========
REGION="us-east-1"
CLUSTER="fastticket-eks"
AWS_PROFILE="default"   # Cambia si usas otro perfil
# ==========================

export AWS_DEFAULT_REGION="$REGION"
export AWS_PROFILE

echo "=== Validating Etapa 1 — EKS Base Infrastructure ==="
echo "Region: $REGION | Cluster: $CLUSTER"
date
echo "----------------------------------------------------"

# 1) AWS CLI & Credentials
echo "[1/8] Checking AWS CLI configuration..."
aws --version || { echo "AWS CLI not installed"; exit 1; }
aws sts get-caller-identity || { echo "AWS credentials invalid"; exit 1; }

# 2) Terraform validation
if [ -d "infra" ]; then cd infra; fi
if [ -f "main.tf" ]; then
  echo "[2/8] Terraform validation..."
  terraform -version
  terraform init -upgrade -reconfigure -input=false
  terraform validate
  echo "Terraform state:"
  terraform state list || echo "No local state yet"
else
  echo "No Terraform configuration found in current directory."
fi
cd ..

# 3) EKS Cluster
echo "[3/8] Checking EKS Cluster status..."
aws eks describe-cluster \
  --name "$CLUSTER" --region "$REGION" \
  --query 'cluster.{Name:name,Status:status,Version:version,Endpoint:endpoint}' \
  --output table || { echo "Cluster not found"; exit 1; }

aws eks update-kubeconfig --name "$CLUSTER" --region "$REGION"
kubectl config current-context

# 4) Nodegroup
echo "[4/8] Checking Nodegroup..."
NG=$(aws eks list-nodegroups --cluster-name "$CLUSTER" --region "$REGION" --query 'nodegroups[0]' --output text)
if [ "$NG" == "None" ] || [ -z "$NG" ]; then
  echo "No nodegroup found."; exit 1;
fi
echo "Nodegroup: $NG"
aws eks describe-nodegroup \
  --cluster-name "$CLUSTER" --nodegroup-name "$NG" --region "$REGION" \
  --query 'nodegroup.{Status:status,Desired:scalingConfig.desiredSize,InstanceTypes:instanceTypes}' \
  --output table

echo "Ready node count:"
kubectl get nodes --no-headers | awk '{print $2}' | grep -c "^Ready$"

# 5) Managed Add-ons
echo "[5/8] Validating managed add-ons..."
aws eks list-addons --cluster-name "$CLUSTER" --region "$REGION"
for ADDON in coredns kube-proxy vpc-cni; do
  echo "→ $ADDON:"
  aws eks describe-addon \
    --cluster-name "$CLUSTER" --addon-name "$ADDON" --region "$REGION" \
    --query 'addon.{Status:status,Version:addonVersion}' \
    --output table || echo "Addon $ADDON missing"
done

# 6) kube-system pods
echo "[6/8] Checking kube-system pods..."
kubectl get pods -n kube-system -o wide
echo "Non-Running pods (should be empty):"
kubectl get pods -n kube-system --no-headers | awk '$3!="Running"{print}' || true

# 7) CoreDNS replicas
echo "[7/8] Validating CoreDNS replicas..."
kubectl get deploy -n kube-system coredns -o jsonpath='{.metadata.name}{" replicas="}{.spec.replicas}{" available="}{.status.availableReplicas}{"\n"}'
echo "(Expected: replicas=1 and available=1)"

# 8) IAM role policies
echo "[8/8] Checking IAM roles..."
CLUSTER_ROLE_ARN=$(aws eks describe-cluster --name "$CLUSTER" --region "$REGION" --query 'cluster.roleArn' --output text)
CLUSTER_ROLE_NAME="${CLUSTER_ROLE_ARN##*/}"
echo "Cluster IAM Role: $CLUSTER_ROLE_NAME"
aws iam list-attached-role-policies --role-name "$CLUSTER_ROLE_NAME" --query 'AttachedPolicies[].PolicyName' --output table

NODE_ROLE_ARN=$(aws eks describe-nodegroup --cluster-name "$CLUSTER" --nodegroup-name "$NG" --region "$REGION" --query 'nodegroup.nodeRole' --output text)
NODE_ROLE_NAME="${NODE_ROLE_ARN##*/}"
echo "Node IAM Role: $NODE_ROLE_NAME"
aws iam list-attached-role-policies --role-name "$NODE_ROLE_NAME" --query 'AttachedPolicies[].PolicyName' --output table

# Optional: instance type
echo "Node instance types:"
kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.status.nodeInfo.instanceType}{"\n"}{end}'

echo "----------------------------------------------------"
echo "✅ Validation complete."
echo "If all items show ACTIVE, Running, and replicas=1 — Etapa 1 passed!"
