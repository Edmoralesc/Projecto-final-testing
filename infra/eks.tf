module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.0"

  # Cluster
  name                   = "fastticket-eks"
  kubernetes_version     = "1.29"
  enable_irsa            = true
  endpoint_public_access = true

  # Networking
  vpc_id     = aws_vpc.this.id
  subnet_ids = [for s in aws_subnet.public : s.id]

  # Access Entries (Cluster Access Management)
  # - Root account admin access for local kubectl
  # - GitHub Actions OIDC role admin access
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
  eks_managed_node_groups = {
    ng_main = {
      name           = "ng-main"
      desired_size   = 1
      min_size       = 1
      max_size       = 1
      capacity_type  = "ON_DEMAND"
      instance_types = ["t3.large"]
      # Prefer AL2023; fallback to AL2 if unsupported
      ami_type = "AL2023_x86_64_STANDARD" # TODO: If unsupported in this region/EKS version, switch to "AL2_x86_64" (AL2 deprecation after EKS 1.32)
      labels   = { workload = "general" }
      tags     = local.tags

      # Use precreated node IAM role with required policies
      iam_role_arn = aws_iam_role.eks_node_role.arn
    }
  }

  tags = local.tags
}

# Managed add-ons (provider resources for compatibility with module v21)
resource "aws_eks_addon" "coredns" {
  cluster_name                = module.eks.cluster_name
  addon_name                  = "coredns"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
  configuration_values        = jsonencode({ replicaCount = 1 })
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