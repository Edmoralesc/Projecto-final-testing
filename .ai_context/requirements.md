# FastTicket — Requisitos del Caso

## Objetivos
- **Velocidad:** deployment < 30 min desde merge/tag.
- **Seguridad:** 0 vulnerabilidades **CRITICAL/HIGH** antes de avanzar de cada Gate.
- **Entregables:** (1) Diagrama del pipeline; (2) Reporte ≤ 500 palabras.

## Stack exigido
- Node.js / Python / React
- AWS + Kubernetes (EKS Spot) + Docker
- **PostgreSQL en EKS** (StatefulSet + PVC)
- **Terraform** para IaC
- **CI/CD:** GitHub Actions

## Evaluación
- Integración DevSecOps … **30%**
- Hardening (containers/k8s) … **25%**
- Lógica del pipeline (7 stages/gates) … **25%**
- Claridad/justificación … **20%**

