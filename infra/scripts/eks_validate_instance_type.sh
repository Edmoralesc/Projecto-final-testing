#!/bin/bash
# eks_validate_instance_type.sh
# Validate if an EC2 instance type is offered in specified AZs for a region.
set -euo pipefail

INSTANCE_TYPE="${1:-m6i.large}"
REGION="${2:-us-east-1}"
AZS_CSV="${3:-us-east-1a,us-east-1d}"

IFS=',' read -r -a AZS <<< "$AZS_CSV"

echo "Checking offerings for $INSTANCE_TYPE in region $REGION and AZs: ${AZS[*]}"

LOCATIONS_JOINED=$(IFS=','; echo "${AZS[*]}")
FOUND=$(aws ec2 describe-instance-type-offerings \
  --region "$REGION" \
  --location-type availability-zone \
  --filters Name=instance-type,Values="$INSTANCE_TYPE" Name=location,Values="$LOCATIONS_JOINED" \
  --query 'InstanceTypeOfferings[].Location' \
  --output text | tr '\t' '\n' | sort -u)

ALL_PRESENT=true
for AZ in "${AZS[@]}"; do
  if ! echo "$FOUND" | grep -qx "$AZ"; then
    echo "- Missing offering in $AZ" >&2
    ALL_PRESENT=false
  fi
done

if $ALL_PRESENT; then
  echo "PASS: $INSTANCE_TYPE is offered in all requested zones: $FOUND"
  exit 0
else
  echo "FAIL: $INSTANCE_TYPE not offered in all specified AZs. Found in: $FOUND" >&2
  exit 2
fi
