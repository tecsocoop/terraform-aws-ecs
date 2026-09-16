variable "name" {
  description = "Cluster name - example: dev-tecso"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID where the ASG will be deployed - example: module.vpc.vpc_id"
  type        = string
}

variable "subnets_ids" {
  description = "Private subnet IDs for the ASG - example: module.vpc.private_subnet_ids_list"
  type        = list(string)
}

variable "alb_security_group_id" {
  description = "Security group ID of the pre-existing ALB allowed to reach ECS container instances on their dynamic host ports"
  type        = string
}

#### ECS INSTANCES

variable "instance_type" {
  description = "Instance type for the ECS container instances ASG - example: t3a.medium"
  type        = string
}

variable "ssh_key_name" {
  description = "AWS key pair name for SSH access (optional; instances are reachable via SSM Session Manager)"
  type        = string
  default     = null
}

variable "asg_min_size" {
  description = "Minimum number of ECS container instances in the ASG"
  type        = number
  default     = 1
}

variable "asg_max_size" {
  description = "Maximum number of ECS container instances in the ASG"
  type        = number
  default     = 1
}

variable "asg_desired_capacity" {
  description = "Desired number of ECS container instances in the ASG"
  type        = number
  default     = 1
}

variable "tags" {
  description = "Additional tags applied to all resources"
  type        = map(string)
  default     = {}
}
