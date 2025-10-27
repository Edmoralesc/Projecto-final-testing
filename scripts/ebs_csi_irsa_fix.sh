#!/usr/bin/env bash
set -euo pipefail

CLUSTER_NAME=${CLUSTER_NAME:-fastticket-eks}
REGION=${REGION:-us-east-1}
ROLE_NAME=${ROLE_NAME:-fastticket-ebs-csi-irsa}
POLICY_ARN="arn:aws:iam::aws:policy/AmazonEBSCSIDriverPolicy"

echo "[init] Using cluster=${CLUSTER_NAME} region=${REGION} role=${ROLE_NAME}" >&2

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
OIDC_ISSUER=$(aws eks describe-cluster --name "${CLUSTER_NAME}" --region "${REGION}" --query "cluster.identity.oidc.issuer" --output text)
OIDC_ID=${OIDC_ISSUER##*/id/}
PROVIDER_ARN="arn:aws:iam::${ACCOUNT_ID}:oidc-provider/oidc.eks.${REGION}.amazonaws.com/id/${OIDC_ID}"

echo "[iam] ACCOUNT_ID=${ACCOUNT_ID} OIDC_ID=${OIDC_ID}" >&2

# Ensure OIDC provider exists (usually created by Terraform/module). If missing, create it.
if ! aws iam get-open-id-connect-provider --open-id-connect-provider-arn "${PROVIDER_ARN}" >/dev/null 2>&1; then
  echo "[iam] Creating OIDC provider ${PROVIDER_ARN}" >&2
  thumbprint=$(openssl s_client -servername oidc.eks.${REGION}.amazonaws.com -showcerts -connect oidc.eks.${REGION}.amazonaws.com:443 </dev/null 2>/dev/null | awk '/BEGIN CERTIFICATE/{flag=1}flag{print}/END CERTIFICATE/{flag=0}' | openssl x509 -fingerprint -noout -sha1 | cut -d'=' -f2 | tr -d ':')
  aws iam create-open-id-connect-provider \
    --url "${OIDC_ISSUER}" \
    --client-id-list sts.amazonaws.com \
    --thumbprint-list "${thumbprint}"
fi

TRUST_POLICY=$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "${PROVIDER_ARN}"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "oidc.eks.${REGION}.amazonaws.com/id/${OIDC_ID}:aud": "sts.amazonaws.com",
          "oidc.eks.${REGION}.amazonaws.com/id/${OIDC_ID}:sub": "system:serviceaccount:kube-system:ebs-csi-controller-sa"
        }
      }
    }
  ]
}
EOF
)

ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${ROLE_NAME}"

if aws iam get-role --role-name "${ROLE_NAME}" >/dev/null 2>&1; then
  echo "[iam] Updating trust policy for role ${ROLE_NAME}" >&2
  aws iam update-assume-role-policy --role-name "${ROLE_NAME}" --policy-document "${TRUST_POLICY}"
else
  echo "[iam] Creating role ${ROLE_NAME}" >&2
  aws iam create-role --role-name "${ROLE_NAME}" --assume-role-policy-document "${TRUST_POLICY}" --description "IRSA for AWS EBS CSI Controller"
fi

# Ensure the managed policy is attached
# Try to find the managed policy ARN (resilient to partitions/accounts)
FOUND_POLICY_ARN=$(aws iam list-policies --scope AWS --only-attached=false \
  --query "Policies[?PolicyName=='AmazonEBSCSIDriverPolicy'].Arn | [0]" --output text 2>/dev/null || true)

if [ -n "${FOUND_POLICY_ARN}" ] && [ "${FOUND_POLICY_ARN}" != "None" ]; then
  POLICY_ARN="${FOUND_POLICY_ARN}"
  ATTACHED=$(aws iam list-attached-role-policies --role-name "${ROLE_NAME}" \
    --query "AttachedPolicies[?PolicyArn=='${POLICY_ARN}'] | length(@)" --output text || echo 0)
  if [ "${ATTACHED}" != "1" ]; then
    echo "[iam] Attaching managed policy to ${ROLE_NAME}: ${POLICY_ARN}" >&2
    aws iam attach-role-policy --role-name "${ROLE_NAME}" --policy-arn "${POLICY_ARN}"
  fi
else
  echo "[iam] Managed policy AmazonEBSCSIDriverPolicy not found. Creating inline fallback policy." >&2
  INLINE_POLICY_NAME="EBSCSIDriverInline"
  TMP_JSON=$(mktemp)
  cat >"${TMP_JSON}" <<'JSON'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ec2:CreateVolume",
        "ec2:CreateTags",
        "ec2:DeleteTags",
        "ec2:DeleteVolume",
        "ec2:AttachVolume",
        "ec2:DetachVolume",
        "ec2:ModifyVolume",
        "ec2:DescribeAvailabilityZones",
        "ec2:DescribeInstances",
        "ec2:DescribeSnapshots",
        "ec2:DescribeTags",
        "ec2:DescribeVolumes",
        "ec2:DescribeVolumeAttribute",
        "ec2:DescribeVolumeStatus"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "kms:CreateGrant",
        "kms:ListGrants",
        "kms:RevokeGrant",
        "kms:Encrypt",
        "kms:Decrypt",
        "kms:DescribeKey",
        "kms:GenerateDataKey*"
      ],
      "Resource": "*"
    }
  ]
}
JSON
  set +e
  aws iam put-role-policy --role-name "${ROLE_NAME}" \
    --policy-name "${INLINE_POLICY_NAME}" \
    --policy-document file://"${TMP_JSON}"
  RC=$?
  set -e
  rm -f "${TMP_JSON}"
  if [ $RC -ne 0 ]; then
    echo "[iam] Warning: put-role-policy failed (rc=$RC). Continuing; role may already have sufficient permissions." >&2
  fi
fi

echo "[eks] Attempting to update addon to use role ${ROLE_ARN}" >&2
set +e
aws eks update-addon \
  --cluster-name "${CLUSTER_NAME}" \
  --addon-name aws-ebs-csi-driver \
  --service-account-role-arn "${ROLE_ARN}" \
  --region "${REGION}" >/dev/null 2>&1
RC=$?
set -e

if [ $RC -ne 0 ]; then
  echo "[eks] update-addon failed; falling back to SA annotation" >&2
  kubectl -n kube-system annotate sa ebs-csi-controller-sa \
    eks.amazonaws.com/role-arn="${ROLE_ARN}" --overwrite
fi

echo "[k8s] Restarting and waiting for ebs-csi-controller rollout" >&2
kubectl -n kube-system rollout restart deploy/ebs-csi-controller || true
kubectl -n kube-system rollout status deploy/ebs-csi-controller --timeout=5m

echo "[done] IRSA fix applied. Role: ${ROLE_ARN}" >&2
