# ACM Section
# Reads an already-issued certificate rather than requesting/validating one
# here — the domain's cert is owned outside this stack so `terraform destroy`
# on the app infra can never take it down.
data "aws_acm_certificate" "ecs_certificate" {
  domain      = var.ecs_domain
  statuses    = ["ISSUED"]
  most_recent = true
  types       = ["AMAZON_ISSUED"]
}


# Route 53 Hosted Zone Section
# Reads the existing hosted zone rather than creating one — the zone is
# foundational, registrar-delegated infrastructure and must outlive this
# stack's destroy pipeline.
data "aws_route53_zone" "ecs_route53_zone" {
  name = var.ecs_route53_domain
}


# Route 53 Record Section
# This is the only DNS resource this stack actually owns — safe to
# create/destroy with the app, since it's just an alias pointing at the ALB.
resource "aws_route53_record" "ecs_domain_record" {
  zone_id         = data.aws_route53_zone.ecs_route53_zone.zone_id
  name            = var.ecs_domain
  type            = "A"
  allow_overwrite = true

  alias {
    name                   = var.ecs_alb_dns_name
    zone_id                = var.ecs_alb_zone_id
    evaluate_target_health = true
  }
}
