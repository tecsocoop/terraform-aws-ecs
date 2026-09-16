output "cluster_name" {
  description = "Name of the ECS cluster."
  value       = aws_ecs_cluster.main.name
}

output "cluster_arn" {
  description = "ARN of the ECS cluster."
  value       = aws_ecs_cluster.main.arn
}

output "capacity_provider_name" {
  description = "Name of the ECS EC2 capacity provider (used in capacity_provider_strategy blocks)."
  value       = aws_ecs_capacity_provider.ec2.name
}

output "ecs_instances_security_group_id" {
  description = "Security group attached to ECS container instances."
  value       = aws_security_group.ecs_instances.id
}

output "ecs_instance_role_arn" {
  description = "ARN of the IAM role assumed by ECS container instances (EC2)."
  value       = aws_iam_role.ecs_instance.arn
}

output "ecs_instance_role_name" {
  description = "Name of the IAM role assumed by ECS container instances (EC2)."
  value       = aws_iam_role.ecs_instance.name
}

output "autoscaling_group_arn" {
  description = "ARN of the ECS container instances Auto Scaling Group."
  value       = aws_autoscaling_group.ecs_instances.arn
}
