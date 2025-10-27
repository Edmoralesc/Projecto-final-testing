# Proveedor OIDC para GitHub Actions
resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
}

# Role que podrán asumir los workflows del repo indicado
data "aws_iam_policy_document" "github_trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    effect  = "Allow"

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # Permite cualquier ref del repo (main, PRs, tags)
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_org_repo}:*"]
    }
  }
}

resource "aws_iam_role" "github_actions" {
  name               = "${local.project}-GitHubOIDC"
  assume_role_policy = data.aws_iam_policy_document.github_trust.json
  tags               = local.tags
}

# Permisos mínimos: describir el cluster (kubeconfig) + lecturas básicas
data "aws_iam_policy_document" "gha_permissions" {
  statement {
    effect = "Allow"
    actions = [
      "eks:DescribeCluster",
      "eks:ListClusters",
      "ec2:Describe*",
      "iam:ListRoles"
    ]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "gha_policy" {
  name   = "${local.project}-gha-eks-min"
  policy = data.aws_iam_policy_document.gha_permissions.json
}

resource "aws_iam_role_policy_attachment" "gha_attach" {
  role       = aws_iam_role.github_actions.name
  policy_arn = aws_iam_policy.gha_policy.arn
}

