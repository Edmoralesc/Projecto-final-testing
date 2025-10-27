variable "aws_region" {
  type = string
}

variable "project_name" {
  type = string
}

variable "env" {
  type    = string
  default = "staging"
}

# VPC
variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

# Availability Zones for the cluster subnets
variable "azs" {
  type    = list(string)
  default = ["us-east-1a", "us-east-1d"]
}

# Node group configuration
variable "node_capacity_type" {
  description = "ON_DEMAND or SPOT"
  type        = string
  default     = "ON_DEMAND"
}

variable "node_instance_types" {
  description = "EC2 instance types for the managed node group"
  type        = list(string)
  default     = ["c6a.large", "m6a.large"]
}

variable "node_ami_type" {
  description = "AL2_x86_64 for x86_64 architecture"
  type        = string
  default     = "AL2_x86_64"
}

variable "node_desired" {
  type    = number
  default = 2
}

variable "node_min" {
  type    = number
  default = 1
}

variable "node_max" {
  type    = number
  default = 2
}

# GitHub repo for OIDC trust condition
variable "github_org_repo" {
  type        = string
  description = "GitHub org/repo for OIDC trust, e.g., 'fercanap/Projecto-final-testing'"
}