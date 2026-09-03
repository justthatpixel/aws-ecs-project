variable "ecs_domain" {
  type    = string
  default = "threat-composer.honeycreators.com"
}

variable "ecs_route53_domain" {
  type    = string
  default = "honeycreators.com"
}

variable "ecs_alb_zone_id" {
  type = string
}

variable "ecs_alb_dns_name" {
  type        = string
  description = "ECS Alb DNS Name"
}
