data "aws_ecr_repository" "threat-composer" {
  name = "threat-composer"
}

resource "aws_ecs_task_definition" "threat-composer" {
  family                   = "threat-composer-app"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"
  network_mode             = "awsvpc"
  execution_role_arn       = aws_iam_role.ecs_execution_role.arn
  task_role_arn            = aws_iam_role.threat_composer_task_role.arn
  runtime_platform {
    cpu_architecture        = "X86_64"
    operating_system_family = "LINUX"
  }
  # container definition 
  container_definitions = jsonencode([
    {
      name      = "threat-composer"
      image     = "${data.aws_ecr_repository.threat-composer.repository_url}:latest"
      essential = true
      portMappings = [
        {
          containerPort = var.ecs_task_port
          protocol      = "tcp"
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.threat-composer.name
          "awslogs-region"        = var.aws_region_current
          "awslogs-stream-prefix" = "ecs"
        }
      }
    }
  ])

}