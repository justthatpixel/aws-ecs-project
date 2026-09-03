variable "ecs_task_port" {
  type        = number
  default     = 80
  description = "Port the container listens on (nginx in our image), and what the ALB target group / SG rules key off"
}

variable "aws_region" {
  type        = string
  default     = "eu-west-2"
  description = "Default aws region for proj"
}
