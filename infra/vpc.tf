resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = merge(local.tags, { Name = "${local.project}-vpc" })
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.this.id
  tags   = merge(local.tags, { Name = "${local.project}-igw" })
}

locals {
  # Mapeo estable de AZ -> índice para evitar conflictos al cambiar la lista var.azs
  az_letter_index = {
    a = 0
    b = 1
    c = 2
    d = 3
    e = 4
    f = 5
  }
}

resource "aws_subnet" "public" {
  for_each = toset(var.azs)
  vpc_id   = aws_vpc.this.id
  # Deriva el índice a partir de la letra de la AZ para generar un CIDR único por AZ,
  # evitando conflictos cuando se cambia la lista de AZs (ej: b -> d)
  cidr_block              = cidrsubnet(var.vpc_cidr, 4, local.az_letter_index[regexall("[a-z]$", each.key)[0]])
  availability_zone       = each.key
  map_public_ip_on_launch = true
  tags = merge(local.tags, {
    Name                     = "${local.project}-public-${each.key}"
    "kubernetes.io/role/elb" = "1"
  })
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id
  tags   = merge(local.tags, { Name = "${local.project}-rt-public" })
}

resource "aws_route" "public_default" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.igw.id
}

resource "aws_route_table_association" "public_assoc" {
  for_each       = aws_subnet.public
  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}

