resource "aws_cloudwatch_log_group" "threat-composer" {
  name              = "/ecs/threat-composer"
  retention_in_days = 365
}



resource "aws_ecs_cluster" "fargate-cluster" {
  name = "ecs-project"
  setting {
    name  = "containerInsights"
    value = "enabled"
  }

}
