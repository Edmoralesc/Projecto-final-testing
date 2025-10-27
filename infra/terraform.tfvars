aws_region      = "us-east-1"
project_name    = "fastticket"
github_org_repo = "fercanap/Projecto-final-testing"

# Node group: fast, stable provisioning on x86_64
node_capacity_type  = "ON_DEMAND"
node_instance_types = ["c6a.large", "m6a.large"]
node_ami_type       = "AL2_x86_64"

# Use AZs a and d as requested
azs = ["us-east-1a", "us-east-1d"]

# Size
node_desired = 2
node_min     = 1
node_max     = 2