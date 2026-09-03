variable "ecs_task_port" {
  type        = number
  default     = 8080
  description = "Port the container listens on — nginx-unprivileged in our image binds 8080, not 80, since it runs as a non-root user"
}

variable "aws_region" {
  type        = string
  default     = "eu-west-2"
  description = "Default aws region for proj"
}

# no-op: forcing a push-triggered CI run to isolate whether workflow_dispatch
# specifically is the variable behind today's repeated OIDC failures.
