#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

OUT_MD="reports/final_report.md"
OUT_PDF="reports/final_report.pdf"
NS="staging"

mkdir -p reports

now(){ date '+%Y-%m-%d %H:%M:%S %Z'; }

cat > "$OUT_MD" << 'EOF'
# FastTicket - Final Report

This document aggregates validation results, security findings, and optimization guidance for the FastTicket project.

EOF

{
  echo "Generated: $(now)"
  echo
  echo "## Infrastructure (Stage 1)"
  echo "- Cluster: fastticket-eks (us-east-1)"
  echo "- Validation: see infra/ and logs/final_validation_summary.log"
  echo
  echo "## Application Deployment (Stage 2)"
  echo "- Namespace: staging"
  echo "- Pods and Services snapshot:" 
  echo '```'
  kubectl -n "$NS" get pods,svc -o wide || true
  echo '```'
  echo
  echo "## CI/CD (Stage 3)"
  echo "- Workflows: ci.yml, cd-staging.yml"
  echo "- Latest runs (use gh to inspect):"
  echo '```'
  if command -v gh >/dev/null 2>&1; then
    gh run list --workflow cd-staging.yml --limit 1 || true
  else
    echo "Install GitHub CLI to query runs."
  fi
  echo '```'
  echo
  echo "## Security Gates (Stage 4)"
  echo "- Trivy, npm audit, pip-audit, tfsec, checkov, ZAP"
  echo "- Artifacts path: reports/"
  echo "- Gate summary: see security-gates-summary artifact if present"
  echo
  echo "### Container Scan (Trivy)"
  echo '```'
  for f in reports/trivy-*.json; do [ -f "$f" ] && echo "$(basename "$f")" && jq -r '.Results[]?.Vulnerabilities[]? | "- [\(.Severity)] \(.VulnerabilityID) \(.Title)"' "$f" | head -n 10 || true; done
  echo '```'
  echo
  echo "### SCA"
  echo "- npm audit: reports/npm-audit.json (top vulnerabilities)"
  echo '```'
  [ -f reports/npm-audit.json ] && jq '.metadata.vulnerabilities' reports/npm-audit.json || echo "No npm audit report"
  echo '```'
  echo "- pip-audit: reports/pip-audit.json"
  echo '```'
  [ -f reports/pip-audit.json ] && jq '.[0:10]' reports/pip-audit.json || echo "No pip-audit report"
  echo '```'
  echo
  echo "### IaC"
  echo "- tfsec: reports/tfsec.sarif"
  echo "- checkov: reports/checkov.(json|sarif)"
  echo
  echo "### DAST (ZAP)"
  echo "- ZAP report: reports/zap/zap.html (if generated)"
  echo
  echo "## Cost (Optimization)"
  START_DATE=$(date -v-7d +%Y-%m-%d 2>/dev/null || date -d "7 days ago" +%Y-%m-%d)
  END_DATE=$(date +%Y-%m-%d)
  echo "- AWS Cost (last 7 days):"
  echo '```'
  aws ce get-cost-and-usage --time-period Start=$START_DATE,End=$END_DATE --granularity DAILY --metrics UnblendedCost 2>/dev/null || echo "Cost Explorer not accessible with current credentials"
  echo '```'
  echo "- Recommendations:"
  echo "  - Keep cluster small (1 node) off-hours or consider pause options"
  echo "  - Use smaller base images and multi-stage builds to reduce image size"
  echo "  - Enable image caching in CI to speed builds"
  echo
  echo "## Final Validation"
  echo "- See logs/final_validation_summary.log for consolidated results"
  echo
  echo "## Appendix"
  echo "- Infra: infra/"
  echo "- Manifests: k8s/"
  echo "- Workflows: .github/workflows/"
  echo "- Scripts: scripts/"
} >> "$OUT_MD"

# Try to make a PDF if pandoc is present
if command -v pandoc >/dev/null 2>&1; then
  pandoc "$OUT_MD" -o "$OUT_PDF" || true
fi

echo "Final report generated at $OUT_MD"
