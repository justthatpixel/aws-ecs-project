resource "aws_vpc" "ecs-project-vpc" {
  cidr_block           = "10.0.0.0/16"
  instance_tenancy     = "default"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "ecs-proj"
  }
}

resource "aws_subnet" "public" {
  for_each          = { for idx, az in var.availability_zones : az => idx }
  vpc_id            = aws_vpc.ecs-project-vpc.id
  availability_zone = each.key
  cidr_block        = cidrsubnet(aws_vpc.ecs-project-vpc.cidr_block, 4, each.value + 1)
  tags              = { Name = "public_${each.key}" }
}

resource "aws_subnet" "private" {
  for_each          = { for idx, az in var.availability_zones : az => idx }
  vpc_id            = aws_vpc.ecs-project-vpc.id
  availability_zone = each.key
  cidr_block        = cidrsubnet(aws_vpc.ecs-project-vpc.cidr_block, 4, each.value + 8)
  tags              = { Name = "private_${each.key}" }
}

resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.ecs-project-vpc.id

  tags = {
    Name = "internet-gateway"
  }
}

# Creating route table

resource "aws_route_table" "public-rt" {
  vpc_id = aws_vpc.ecs-project-vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }

  tags = {
    Name = "public-route-table"
  }
}

resource "aws_route_table" "private-rt" {
  vpc_id = aws_vpc.ecs-project-vpc.id

  tags = {
    Name = "private-route-table"
  }
}

# Associating route table with public subnets

resource "aws_route_table_association" "public_az1" {
  subnet_id      = aws_subnet.public["eu-west-2a"].id
  route_table_id = aws_route_table.public-rt.id
}

resource "aws_route_table_association" "public_az2" {
  subnet_id      = aws_subnet.public["eu-west-2b"].id
  route_table_id = aws_route_table.public-rt.id
}

resource "aws_route_table_association" "private_az1" {
  subnet_id      = aws_subnet.private["eu-west-2a"].id
  route_table_id = aws_route_table.private-rt.id
}

resource "aws_route_table_association" "private_az2" {
  subnet_id      = aws_subnet.private["eu-west-2b"].id
  route_table_id = aws_route_table.private-rt.id
}

# VPC-endpoint security group — owned entirely inside this module since
# nothing outside the VPC's own internal traffic needs to reach these
# endpoints. Scoped to the VPC's own CIDR rather than referencing the ECS
# task SG, which keeps this module fully self-contained (no inputs needed).
resource "aws_security_group" "vpc-endpoint" {
  vpc_id      = aws_vpc.ecs-project-vpc.id
  description = "Security group for the ECR/CloudWatch interface VPC endpoints"
}

resource "aws_vpc_security_group_ingress_rule" "endpoints_ingress" {
  security_group_id = aws_security_group.vpc-endpoint.id
  description       = "Allow HTTPS from anything inside this VPC"
  cidr_ipv4         = aws_vpc.ecs-project-vpc.cidr_block
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "endpoints_egress" {
  security_group_id = aws_security_group.vpc-endpoint.id
  description       = "Allow all outbound traffic from the endpoint ENIs"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.ecs-project-vpc.id
  service_name      = "com.amazonaws.${var.aws_region_current}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.private-rt.id]
}

# Creating interface endpoints for ECR and CloudWatch logs
resource "aws_vpc_endpoint" "interface_endpoints" {
  for_each = {
    "dkr"  = "com.amazonaws.${var.aws_region_current}.ecr.dkr"
    "api"  = "com.amazonaws.${var.aws_region_current}.ecr.api"
    "logs" = "com.amazonaws.${var.aws_region_current}.logs"
  }

  vpc_id              = aws_vpc.ecs-project-vpc.id
  service_name        = each.value
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  security_group_ids  = [aws_security_group.vpc-endpoint.id]
  subnet_ids          = [for subnet in aws_subnet.private : subnet.id] # Get the ids of each private subnet
}
