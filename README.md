FastTicket — CI/CD y DevSecOps (AWS EKS)

Resumen del pipeline
- CI (Pull Requests y branches):
   - Backend: Python 3.12 + pytest.
   - Frontend: Node 20 + npm test y build.
   - SCA: pip-audit (api/) y npm audit (frontend/). Reportes como artifacts.
   - Build & Scan: imágenes Docker (backend/frontend) y Trivy (HIGH/CRITICAL) sin push en CI.
- Security Gates (en PRs o manual): tfsec y Checkov (infra/), Trivy sobre imágenes :staging, ZAP Baseline (DAST) con port-forward al backend. Gates fallan si superan umbrales de severidad.
- CD a Staging (main): build & push a docker.io/fercanap (o GHCR fallback), despliegue kustomize a ns=staging (EKS us-east-1), patch de imágenes :staging y smoke test /health.

Entornos
- Dev: port-forward y pruebas locales. Costos mínimos.
- Staging: EKS fastticket-eks (ns=staging), 1 réplica, gp3 para Postgres, secrets/ConfigMaps, probes, RBAC. Servicios internos (ClusterIP) y, cuando se requiere validación pública, Services type LoadBalancer temporales.
- Prod: promoción de tag aprobado, escalamiento, TLS/Ingress.

Validaciones y acceso público (opcional)
1) Prechequeos y exposición pública temporal:
    - bash scripts/public_expose_prereqs.sh
    - bash scripts/expose_public_lb.sh
2) Validar endpoints públicos (usa IP si DNS no ha propagado):
    - bash scripts/validate_public_access.sh
3) Remover LoadBalancers para evitar costos:
    - bash scripts/cleanup_public_lb.sh

Seguridad y hardening
- OIDC GitHub→AWS (sin llaves). Imágenes con tags inmutables :staging.
- RBAC por namespace, secrets Kubernetes, recursos/limits y readiness/liveness.
- Escaneo SAST (CodeQL), SCA (pip-audit/npm audit), contenedores (Trivy), Dockerfiles (Hadolint), IaC (tfsec/Checkov) y DAST (ZAP Baseline) en staging vía port-forward.

Apagar y auditar costos en AWS
- Auditar recursos y estimación de costos: 
   - bash scripts/audit_and_shutdown_aws.sh --audit
- Apagar (escalado a 0, eliminar LB, borrar nodegroups/cluster con confirmación):
   - bash scripts/audit_and_shutdown_aws.sh --shutdown
- Destruir toda la infraestructura de Terraform:
   - bash scripts/audit_and_shutdown_aws.sh --destroy-terraform

Documentación del entregable
- Versión Markdown: docs/entregable2.md
- Documento final (DOCX): docs/2.Entregable CI_CD testing pipeline.docx

# FastTicket DevSecOps Case Study

FastTicket is a small full-stack application (FastAPI backend, React frontend, PostgreSQL) deployed on AWS EKS with a secure, low-cost, and automated DevSecOps pipeline.

This repository includes:
- Infrastructure as Code (Terraform) to provision a minimal EKS cluster and networking
- Kubernetes manifests with Kustomize overlays for staging
- CI/CD via GitHub Actions (build/test/scan/deploy)
- Security Gates (SAST, SCA, Container, IaC, DAST)
- Validation scripts for each stage and a new cost-control orchestration

## Project stages overview

1. Stage 1 – Infrastructure readiness and EKS
   - Terraform plans, EKS health checks, kube-system validation, evidence capture
2. Stage 2 – Kubernetes Deployments
   - Base + overlays (staging), StorageClass gp3, Postgres StatefulSet, backend/frontend
3. Stage 3 – CI/CD
   - CI for tests and scans; CD to EKS using GitHub OIDC
4. Stage 4 – Security Gates
   - SAST (CodeQL), SCA (pip-audit/npm audit), Container (Trivy), IaC (tfsec/checkov), DAST (ZAP)
5. Stage 5 – Final validation
   - Consolidated validation, report generation, cleanup helpers

Each stage is backed by scripts in `scripts/` and workflows in `.github/workflows/`.

## CI/CD pipeline summary

The pipeline uses GitHub Actions with OIDC to AWS:
- CI: unit tests (Python/Node), SCA (pip-audit, npm audit), and container build + Trivy image scans.
- Security Gates: SAST (CodeQL), SCA, Container, IaC (tfsec/Checkov), and DAST (OWASP ZAP Baseline via port-forward to backend).
- CD (staging): build and push images to docker.io/fercanap (or GHCR fallback), apply `k8s/overlays/staging`, patch images to `:staging`, rollout and smoke test `/health`.
- Deploy to prod is modeled as a manual approval after all gates PASS.

## Cost Control and Shutdown

To avoid surprise AWS charges in us-east-1, use the orchestrator below. It is safe by default, interactive for destructive operations, and supports dry-run mode.

Quick usage:

```bash
# Audit only (default)
scripts/audit_and_shutdown_aws.sh --audit

# Safe shutdown (interactive)
scripts/audit_and_shutdown_aws.sh --shutdown

# Dry run the shutdown plan
scripts/audit_and_shutdown_aws.sh --dry-run --shutdown

# Restore minimal infra (no app deploys)
scripts/audit_and_shutdown_aws.sh --restore-minimal

# Destroy all Terraform-managed resources
scripts/audit_and_shutdown_aws.sh --destroy-terraform
```

What it touches:
- EKS cluster and node groups (control-plane hourly cost + worker nodes)
- ELB/NLB from Kubernetes Services of type LoadBalancer
- EBS volumes from PersistentVolumeClaims (PVCs)
- EC2 instances and ENIs belonging to the cluster
- CloudWatch log groups under `/aws/eks/fastticket-eks/*`
- ECR repositories (listed only by default)

Safety behaviors:
- `--dry-run` shows actions without executing them
- Double-confirmation for node group and cluster deletion, and for emptying/deleting S3 buckets
- PVCs/data are retained by default; pass `--delete-persistent-data` only if you want to remove data volumes (not enabled by default in the script)
- Always saves evidence to `validation_output/cost/<timestamp>/` and human-readable logs to `logs/`

Expected hourly cost avoided:
- EKS control-plane ~ $0.10/hour
- Each t3.small/large worker ~ $0.02–$0.06/hour (on-demand); SPOT can be much cheaper with interruption risk

How to re-create the environment:

```bash
# Recreate minimal infra (VPC + EKS + node group)
(cd infra && terraform init -upgrade && terraform apply -auto-approve)

# Deploy application workloads to staging
kubectl apply -k k8s/overlays/staging
```

Notes:
- Use Service type `ClusterIP` internally to avoid ELB costs. Prefer Ingress or port-forwarding during development.
- Right-size `resources.requests/limits` to keep nodes small.

## Validation scripts

- Stage 1: `scripts/validate_stage1_prereqs.sh`, `scripts/validate_stage1_infra.sh`
- Stage 2: `scripts/validate_stage2_prereqs.sh`, `scripts/validate_stage2_deployment.sh`
- Stage 3: `scripts/validate_stage3_prereqs.sh`, `scripts/validate_stage3_pipeline.sh`
- Stage 4: `scripts/validate_stage4_prereqs.sh`, `scripts/validate_stage4_results.sh`
- Stage 5: `scripts/validate_stage5_prereqs.sh`, `scripts/final_validation.sh`, `scripts/generate_final_report.sh`, `scripts/cleanup_resources.sh`
- Cost: `scripts/audit_and_shutdown_aws.sh` (uses `scripts/_cost_helpers.sh`)

Artifacts are written to `validation_output/` and human logs to `logs/`.

## Public exposure validation (optional)

To briefly expose the app over the internet for demonstrations, we provide two Services of type LoadBalancer and validation helpers.

```bash
# Check prerequisites and warn about ELB costs
bash scripts/public_expose_prereqs.sh

# Create public LoadBalancers and wait for endpoints
bash scripts/expose_public_lb.sh

# Validate backend /health and frontend / over public IP/hostname
bash scripts/validate_public_access.sh

# Cleanup to stop ELB costs
bash scripts/cleanup_public_lb.sh
```

Note: Keep LoadBalancers only as long as needed; they incur hourly charges.

## One-command deployment from scratch

Use the following script to provision the AWS infrastructure (Terraform), wait until EKS and nodes are ready, deploy the Kubernetes workloads to the `staging` namespace, and validate with the existing Stage scripts. It adds sensible waits between steps.

Quick usage:

```bash
scripts/deploy_from_scratch.sh
```

What it does:
- Runs Stage 1 prereq validation and Terraform apply for VPC/EKS/node group
- Waits for the EKS cluster to become ACTIVE and for nodes to be Ready
- Updates kubeconfig for the cluster
- Applies `k8s/overlays/staging` and waits for Postgres, Backend, and Frontend to roll out
- Reuses Stage 2 validators to confirm service health/connectivity
- Writes logs to `logs/deploy_<timestamp>.log` and a summary to `validation_output/deploy/<timestamp>/summary.json`

Prerequisites:
- AWS credentials configured for us-east-1
- Tools: aws, kubectl, terraform, jq

Notes:
- The script is idempotent with Terraform; repeated runs will converge infra to declared state.
- For complete teardown, see the Cost Control section above.

## Troubleshooting

- If GitHub OIDC deploys fail, verify the trust condition in `infra/iam_github_oidc.tf` matches `github_org_repo` in `terraform.tfvars`.
- For Kubernetes API access, ensure your IAM identity has admin access via `access_entries` in `infra/eks.tf`.
- For EBS CSI driver, ensure the addon is installed with proper IRSA.
