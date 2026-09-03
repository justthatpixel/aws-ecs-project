resource "aws_ecs_service" "threat-composer-service" {
  name            = "threat-composer"
  launch_type     = "FARGATE"
  cluster         = aws_ecs_cluster.fargate-cluster.id
  task_definition = aws_ecs_task_definition.threat-composer.arn
  desired_count   = 2
  depends_on      = [aws_iam_role_policy_attachment.ecs_execution_role_policy]

  load_balancer {
    target_group_arn = var.ecs_alb_target_group_arn
    container_name   = "threat-composer"
    container_port   = var.ecs_task_port
  }

  network_configuration {
    subnets          = [var.ecs_subnet_private_2a_id, var.ecs_subnet_private_2b_id]
    security_groups  = [var.ecs_service_sg_id]
    assign_public_ip = false
  }
}
