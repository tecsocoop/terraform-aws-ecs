output "cluster_name" {
  description = "Name of the ECS cluster."
  value       = aws_ecs_cluster.main.name
}

output "cluster_arn" {
  description = "ARN of the ECS cluster."
  value       = aws_ecs_cluster.main.arn
}

output "capacity_providers" {
  description = "EC2 capacity providers keyed by capacity_providers input key."
  value = {
    for key, capacity_provider in aws_ecs_capacity_provider.ec2 : key => {
      name = capacity_provider.name
      arn  = capacity_provider.arn
    }
  }
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

output "autoscaling_groups" {
  description = "Auto Scaling Groups keyed by capacity_providers input key."
  value = {
    for key, autoscaling_group in aws_autoscaling_group.ecs_instances : key => {
      arn  = autoscaling_group.arn
      name = autoscaling_group.name
    }
  }
}
