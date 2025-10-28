# FastTicket - Final Report

This document aggregates validation results, security findings, and optimization guidance for the FastTicket project.

Generated: 2025-10-27 13:21:33 CST

## Infrastructure (Stage 1)
- Cluster: fastticket-eks (us-east-1)
- Validation: see infra/ and logs/final_validation_summary.log

## Application Deployment (Stage 2)
- Namespace: staging
- Pods and Services snapshot:
```
NAME                            READY   STATUS    RESTARTS   AGE     IP            NODE                         NOMINATED NODE   READINESS GATES
pod/backend-6779ff774-2fls9     1/1     Running   0          4h18m   10.0.51.164   ip-10-0-51-38.ec2.internal   <none>           <none>
pod/frontend-5c486bb788-zp67n   1/1     Running   0          4h18m   10.0.54.15    ip-10-0-51-38.ec2.internal   <none>           <none>
pod/postgres-0                  1/1     Running   0          4h18m   10.0.61.29    ip-10-0-51-38.ec2.internal   <none>           <none>

NAME                      TYPE           CLUSTER-IP       EXTERNAL-IP                                                               PORT(S)        AGE     SELECTOR
service/backend           ClusterIP      172.20.55.204    <none>                                                                    8080/TCP       4h18m   app.kubernetes.io/managed-by=kustomize,app.kubernetes.io/name=fastticket-backend
service/backend-public    LoadBalancer   172.20.125.169   adeb92fdb30184f19a117d36cc07b3cb-493337718.us-east-1.elb.amazonaws.com    80:30192/TCP   12m     app.kubernetes.io/name=fastticket-backend
service/frontend          ClusterIP      172.20.159.151   <none>                                                                    3000/TCP       4h18m   app.kubernetes.io/managed-by=kustomize,app.kubernetes.io/name=fastticket-frontend
service/frontend-public   LoadBalancer   172.20.55.193    a7fc2c34fa13b4e69a65aa8d512ae0ad-1533148601.us-east-1.elb.amazonaws.com   80:32491/TCP   12m     app.kubernetes.io/name=fastticket-frontend
service/postgres          ClusterIP      172.20.27.167    <none>                                                                    5432/TCP       4h18m   app.kubernetes.io/managed-by=kustomize,app.kubernetes.io/name=fastticket-postgres
```

## CI/CD (Stage 3)
- Workflows: ci.yml, cd-staging.yml
- Latest runs (use gh to inspect):
```
completed	success	CD - Staging	CD - Staging	main	workflow_dispatch	18852750331	1m35s	2025-10-27T19:01:50Z
```

## Security Gates (Stage 4)
- Trivy, npm audit, pip-audit, tfsec, checkov, ZAP
- Artifacts path: reports/
- Gate summary: see security-gates-summary artifact if present

### Container Scan (Trivy)
```
```

### SCA
- npm audit: reports/npm-audit.json (top vulnerabilities)
```
No npm audit report
```
- pip-audit: reports/pip-audit.json
```
No pip-audit report
```

### IaC
- tfsec: reports/tfsec.sarif
- checkov: reports/checkov.(json|sarif)

### DAST (ZAP)
- ZAP report: reports/zap/zap.html (if generated)


## Appendix
- Infra: infra/
- Manifests: k8s/
- Workflows: .github/workflows/
- Scripts: scripts/
