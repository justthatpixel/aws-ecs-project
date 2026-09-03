output "target_group_arn" {
  value = aws_lb_target_group.threat-composer.arn
}

output "ecs_alb_dns_name" {
  value = aws_lb.ecs-project-alb.dns_name
}

output "alb_arn" {
  value = aws_lb.ecs-project-alb.arn
}

output "ecs_alb_zone_id" {
  value = aws_lb.ecs-project-alb.zone_id
}
