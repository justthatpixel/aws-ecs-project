output "vpc_id" {
  value = aws_vpc.ecs-project-vpc.id
}

output "vpc_cidr_block" {
  value = aws_vpc.ecs-project-vpc.cidr_block
}

output "ecs_subnet_public_2a_id" {
  value = aws_subnet.public["eu-west-2a"].id
}

output "ecs_subnet_public_2b_id" {
  value = aws_subnet.public["eu-west-2b"].id
}

output "ecs_subnet_private_2a_id" {
  value = aws_subnet.private["eu-west-2a"].id
}

output "ecs_subnet_private_2b_id" {
  value = aws_subnet.private["eu-west-2b"].id
}
