resource "aws_security_group" "alb" {
  vpc_id      = var.vpc_id
  description = "Security group for the public-facing ALB"
}

resource "aws_security_group" "ecs-service" {
  vpc_id      = var.vpc_id
  description = "Security group for the ECS service tasks"
}

# ALB ingress/egress

resource "aws_vpc_security_group_ingress_rule" "alb_https" {
  security_group_id = aws_security_group.alb.id
  description       = "Allow inbound HTTPS from the internet"
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "alb_http" {
  security_group_id = aws_security_group.alb.id
  description       = "Allow inbound HTTP from the internet — redirected to HTTPS at the listener"
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 80
  to_port           = 80
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "alb_all_outbound" {
  security_group_id = aws_security_group.alb.id
  description       = "Allow all outbound traffic from the ALB"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

# ECS service ingress/egress — only reachable from the ALB, on the
# container's own port

resource "aws_vpc_security_group_ingress_rule" "ecs_from_alb_ingress" {
  security_group_id            = aws_security_group.ecs-service.id
  description                  = "Allow inbound traffic from the ALB security group only"
  referenced_security_group_id = aws_security_group.alb.id
  from_port                    = var.ecs_task_port
  to_port                      = var.ecs_task_port
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "ecs_egress" {
  security_group_id = aws_security_group.ecs-service.id
  description       = "Allow all outbound traffic from ECS tasks (needed for VPC endpoints, ECR/CloudWatch access)"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}
