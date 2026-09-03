variable "aws_region_current" {
  type    = string
  default = "eu-west-2"
}

variable "ecs_subnet_private_2a_id" {
  type = string
}

variable "ecs_subnet_private_2b_id" {
  type = string
}

variable "ecs_alb_target_group_arn" {
  type = string
}

variable "ecs_service_sg_id" {
  type = string
}

variable "ecs_task_port" {
  type = number
}
