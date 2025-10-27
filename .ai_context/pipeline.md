# Pipeline DevSecOps (7 stages)

1) **CODE (Shift-Left)**
   - Unit tests (Pytest/Jest) + coverage ≥ 80%
   - Lint + **Gitleaks** (no secrets)
   - ✅ Gate: coverage ≥ 80% + sin secretos

2) **BUILD & SCA**
   - Docker build (api, frontend)
   - **Trivy SCA** (deps) + **Trivy image** (antes de push)
   - ✅ Gate: 0 **CRITICAL/HIGH**

3) **SAST**
   - **CodeQL** y/o **Semgrep** (Node/Python/React)
   - ✅ Gate: 0 **High**

4) **DEPLOY TO STAGING**
   - Push a Docker Hub (`fercanap/...`)
   - Deploy a **EKS/staging** + `rollout status`
   - ✅ Gate: `/health` 200 + pods Ready

5) **TEST & DAST**
   - E2E (Playwright/Cypress) en STAGING_URL
   - **OWASP ZAP** (baseline/full)
   - ✅ Gate: 0 **E2E fails** + 0 **High/Medium** DAST

6) **HARDENING FINAL**
   - **Trivy config** (K8s/Dockerfile)
   - **Conftest/OPA**: `runAsNonRoot`, `readOnlyRootFilesystem`, `capDrop: ["ALL"]`, `seccompProfile: RuntimeDefault`, `resources`, `probes`, **NetworkPolicy** deny-by-default
   - ✅ Gate: políticas OK

7) **DEPLOY TO PROD**
   - Canary/Blue-Green + **smoke tests** (200 OK + query DB)
   - ✅ Gate: smoke green (promote) / rollback si falla

