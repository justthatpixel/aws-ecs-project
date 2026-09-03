output "vpc_id" {
  value = module.vpc.vpc_id
}

output "alb_dns_name" {
  value = module.alb.ecs_alb_dns_name
}

output "ecs_cluster_arn" {
  value = module.ecs.cluster_arn
}

output "ecs_service_name" {
  value = module.ecs.service_name
}

output "route53_nameservers" {
  value = module.acm.nameservers
}

output "acm_certificate_arn" {
  value = module.acm.certificate_arn
}
