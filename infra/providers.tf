provider "aws" {
  region = var.aws_region
}

locals {
  project = var.project_name
  tags = {
    Project = local.project
    Owner   = "fercanap"
    Env     = var.env
  }
}

