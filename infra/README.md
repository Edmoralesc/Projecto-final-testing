# Infra FastTicket (Terraform)

## Prerrequisitos
- Terraform >= 1.5, AWS CLI, kubectl
- AWS account configurada (us-east-1)

## Pasos
```bash
cd infra
terraform init
terraform plan
terraform apply -auto-approve
aws eks update-kubeconfig --region us-east-1 --name fastticket-eks
kubectl get nodes

