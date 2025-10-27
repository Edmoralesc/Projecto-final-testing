module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.0"

  # Cluster
  name               = "fastticket-eks"
  kubernetes_version = "1.29"
  enable_irsa        = true
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
          policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = { type = "cluster" }
        }
      }
    }

    github_actions = {
      principal_arn = aws_iam_role.github_actions.arn
      policy_associations = {
        admin = {
          policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = { type = "cluster" }
        }
      }
    }
  }

  # Managed node group (x86_64 ON_DEMAND)
  eks_managed_node_groups = {
    ng_main = {
      name           = "ng-main"
      desired_size   = var.node_desired
      min_size       = var.node_min
      max_size       = var.node_max
      capacity_type  = var.node_capacity_type
      instance_types = var.node_instance_types
      ami_type       = var.node_ami_type # AL2_x86_64
      labels         = { workload = "general" }
      tags           = local.tags
    }
  }

  tags = local.tags
}