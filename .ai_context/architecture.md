# Arquitectura Técnica

- **Frontend:** React (Nginx container)
- **Backend:** Python (FastAPI)
- **DB:** PostgreSQL como StatefulSet en EKS (PVC + init.sql)
- **Containers:** Docker; registry: Docker Hub (públicas)
- **Orquestación:** Kubernetes EKS (Spot nodes)
- **CI/CD:** GitHub Actions + OIDC a AWS
- **IaC:** Terraform (VPC, EKS, IAM OIDC; *sin RDS*)
- **Security tooling:** Gitleaks, Trivy (SCA/image/config), CodeQL/Semgrep (SAST), ZAP (DAST), Conftest (OPA)
- **Entornos:** 
  - **Dev:** Docker Compose (FE+API+DB)
  - **Staging/Prod:** EKS namespaces separados; HPA, PDB, NetworkPolicy

