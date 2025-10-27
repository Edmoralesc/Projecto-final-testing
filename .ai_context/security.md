# Seguridad

## Shift-Left (antes de deploy)
- **Gitleaks** en PR: sin credenciales expuestas.
- **SCA/SAST**: Trivy (deps) + CodeQL/Semgrep = 0 High/Critical.
- Coverage ≥ 80%.

## Run-time/Continuous
- **DAST** ZAP en Staging: 0 High/Medium.
- **Hardening**: OPA/Conftest + Trivy config (no-root, FS RO, caps mínimas, probes, limits, NetworkPolicy).
- **Supply chain**: imágenes públicas, tag por SHA; (opcional) cosign.

## Post-deploy
- Smoke tests + rollback auto.
- Cost-control: teardown con `terraform destroy` al finalizar.

