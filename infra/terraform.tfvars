aws_region      = "us-east-1"
project_name    = "fastticket"
github_org_repo = "fercanap/Projecto-final-testing"

# Minimal EKS nodegroup (Free Tier eligible)
node_capacity_type  = "ON_DEMAND"
node_instance_types = ["t3.large"]
node_ami_type       = "AL2023_x86_64_STANDARD" # Fallback: "AL2_x86_64" (AL2 deprecation after EKS 1.32)

# IMPORTANT: EKS requires at least two subnets in different AZs for the control plane.
# Keep two AZs to ensure cluster creation succeeds while remaining Free Tier on nodes.
azs = ["us-east-1a", "us-east-1d"]

# Minimal node scaling
node_desired = 1
node_min     = 1
node_max     = 1