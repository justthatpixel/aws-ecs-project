variable "vpc_id" {
  type = string
}

variable "alb_sg_id" {
  type = string
}

variable "ecs_task_port" {
  type = number
}

variable "alb_subnet_public" {
  type        = list(string)
  description = "Public subnet ids the ALB is deployed into"
}

variable "ecs_domain" {
  type    = string
  default = "threat-composer.honeycreators.com"
}
