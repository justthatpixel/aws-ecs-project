output "certificate_arn" {
  value = data.aws_acm_certificate.ecs_certificate.arn
}

output "route53_zone_id" {
  value = data.aws_route53_zone.ecs_route53_zone.zone_id
}

output "nameservers" {
  value = data.aws_route53_zone.ecs_route53_zone.name_servers
}
