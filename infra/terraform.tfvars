aws_region      = "us-east-1"             # Primary AWS region for all resources (EKS, VPC, nodes)
project_name    = "fastticket"            # Used in resource names and tags (e.g., Name=fastticket-*)
github_org_repo = "fercanap/Projecto-final-testing" # GitHub org/repo used for OIDC trust (CI deploys without long-lived keys)

# Minimal EKS nodegroup (Free Tier eligible)
node_capacity_type  = "ON_DEMAND"              # ON_DEMAND for predictability; use SPOT to cut EC2 costs with potential interruptions
node_instance_types = ["t3.large"]            # Node size drives EC2 spend; t3.large ~2 vCPU/8GiB RAM
node_ami_type       = "AL2023_x86_64_STANDARD" # Preferred; fallback: "AL2_x86_64" (AL2 deprecation after EKS 1.32)

# IMPORTANT: EKS requires at least two subnets in different AZs for the control plane.
# Keep two AZs to ensure cluster creation succeeds while remaining Free Tier on nodes.
azs = ["us-east-1a", "us-east-1d"]            # Two public subnets in separate AZs are required by EKS control plane

# Minimal node scaling
node_desired = 1                               # Keep at 1 to minimize cost; scale to 0 only after cluster exists
node_min     = 1
node_max     = 1