terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = "eu-west-2"
}

# Foundational, registrar-delegated infrastructure — deliberately owned
# here, in its own bootstrap state, and NOT by the main app stack. A
# `terraform destroy` on the app infra (modules/vpc, modules/alb, etc.)
# must never be able to take this zone down; the acm module only ever
# reads it via a data source.
resource "aws_route53_zone" "honeycreators" {
  name = "honeycreators.com"

  lifecycle {
    prevent_destroy = true
  }
}

output "nameservers" {
  value = aws_route53_zone.honeycreators.name_servers
}

output "zone_id" {
  value = aws_route53_zone.honeycreators.zone_id
}
