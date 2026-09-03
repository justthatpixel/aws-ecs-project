output "cluster_arn" {
  value = aws_ecs_cluster.fargate-cluster.arn
}

output "service_name" {
  value = aws_ecs_service.threat-composer-service.name
}
