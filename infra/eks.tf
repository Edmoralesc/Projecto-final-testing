## EKS cluster and managed node group (core control-plane cost + worker nodes)
## Cost notes:
## - EKS control-plane charges per-hour even with 0 nodes; consider deleting cluster to stop cost.
## - Node instance_types and desired_size directly impact EC2 spend.
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.0"

  # Cluster
  name                   = "fastticket-eks"   # Cluster name used for tags and Kubernetes discovery
  kubernetes_version     = "1.29"             # Pinned minor version for stability
  enable_irsa            = true               # Enable IAM Roles for Service Accounts (secure add-on access)
  endpoint_public_access = true               # Public API endpoint; restrict via security groups for production

  # Networking
  vpc_id     = aws_vpc.this.id                # Attach cluster to our VPC
  subnet_ids = [for s in aws_subnet.public : s.id] # Use public subnets for simplicity (incurs NAT/egress via IGW)

  # Access Entries (Cluster Access Management)
  # - Root account admin access for local kubectl
  # - GitHub Actions OIDC role admin access
  # Grant admin access to root and GitHub Actions OIDC role to enable CI/CD deployments safely
  access_entries = {
    cluster_creator = {
      principal_arn = "arn:aws:iam::665516437576:root"
      policy_associations = {
        admin = {
          policy_arn   = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = { type = "cluster" }
        }
      }
    }

    github_actions = {
      principal_arn = aws_iam_role.github_actions.arn
      policy_associations = {
        admin = {
          policy_arn   = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = { type = "cluster" }
        }
      }
    }
  }

  # Managed node group (x86_64 ON_DEMAND)
  # Single managed node group (x86_64 ON_DEMAND)
  eks_managed_node_groups = {
    ng_main = {
      name           = "ng-main"
      desired_size   = 1                     # Keep minimal to reduce cost; increase for load
      min_size       = 1
      max_size       = 1
      capacity_type  = "ON_DEMAND"           # Change to SPOT to reduce cost with interruption risk
      instance_types = ["t3.large"]          # ~2 vCPU/8GiB; adjust based on workload
      # Prefer AL2023; fallback to AL2 if unsupported
  ami_type = "AL2023_x86_64_STANDARD"   # Prefer AL2023; fallback AL2 (deprecated after EKS 1.32)
  labels   = { workload = "general" }
  tags     = local.tags                  # Propagate project/env tags for cost tracking

      # Use precreated node IAM role with required policies
      iam_role_arn = aws_iam_role.eks_node_role.arn # Pre-created node role with EKS and CNI policies
    }
  }

  tags = local.tags
}

## Managed add-ons: Core EKS components managed by AWS (no extra module cost)
resource "aws_eks_addon" "coredns" {
  cluster_name                = module.eks.cluster_name
  addon_name                  = "coredns"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
  configuration_values        = jsonencode({ replicaCount = 1 }) # Scale down on tiny clusters to save memory/CPU
}

resource "aws_eks_addon" "kube_proxy" {
  cluster_name                = module.eks.cluster_name
  addon_name                  = "kube-proxy"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
}

resource "aws_eks_addon" "vpc_cni" {
  cluster_name                = module.eks.cluster_name
  addon_name                  = "vpc-cni"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
}