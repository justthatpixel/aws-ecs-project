# Looked up directly here (not passed in from the acm module) so this
# module has no dependency on anything downstream of it — acm depends on
# alb's outputs, never the other way around.
data "aws_acm_certificate" "ecs_certificate" {
  domain      = var.ecs_domain
  statuses    = ["ISSUED"]
  most_recent = true
  types       = ["AMAZON_ISSUED"]
}

resource "aws_lb" "ecs-project-alb" {
  name                       = "ecs-project-alb"
  internal                   = false
  load_balancer_type         = "application"
  security_groups            = [var.alb_sg_id]
  subnets                    = var.alb_subnet_public
  drop_invalid_header_fields = true

  enable_deletion_protection = false

  tags = {
    Environment = "production"
  }
}

# Create listener for HTTP traffic on port 80
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.ecs-project-alb.arn
  port              = "80"
  protocol          = "HTTP"
  default_action {
    type = "redirect"
    redirect {
      protocol    = "HTTPS"
      port        = "443"
      status_code = "HTTP_301"
    }
  }
}

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.ecs-project-alb.arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-2016-08"
  certificate_arn   = data.aws_acm_certificate.ecs_certificate.arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.threat-composer.arn
  }
}

# Creating target group for ECS service
resource "aws_lb_target_group" "threat-composer" {
  name        = "threat-composer-tg"
  port        = var.ecs_task_port
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = var.vpc_id

  health_check {
    path                = "/"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
    matcher             = "200-399"
  }
}
