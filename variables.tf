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

#### ECS CAPACITY PROVIDERS

variable "ssh_key_name" {
  description = "AWS key pair name for SSH access (optional; instances are reachable via SSM Session Manager)"
  type        = string
  default     = null
}

variable "capacity_providers" {
  description = <<-EOT
    Map of EC2 capacity provider configurations. Each entry creates an ECS
    capacity provider, a dedicated Auto Scaling Group, and a launch template.
    The map key is the stable Terraform identity and suffix is appended to the
    cluster name when naming AWS resources.
  EOT

  type = map(object({
    suffix           = string
    instance_type    = string
    desired_capacity = number
    min_size         = number
    max_size         = number
  }))

  validation {
    condition = alltrue([
      for capacity_provider in values(var.capacity_providers) :
      capacity_provider.min_size >= 0 &&
      capacity_provider.min_size <= capacity_provider.desired_capacity &&
      capacity_provider.desired_capacity <= capacity_provider.max_size
    ])
    error_message = "Each capacity provider must satisfy: 0 <= min_size <= desired_capacity <= max_size."
  }

  validation {
    condition = alltrue([
      for capacity_provider in values(var.capacity_providers) :
      length(trimspace(capacity_provider.suffix)) > 0
      ]) && length(distinct([
        for capacity_provider in values(var.capacity_providers) : capacity_provider.suffix
    ])) == length(var.capacity_providers)
    error_message = "Each capacity provider suffix must be non-empty and unique."
  }
}

variable "tags" {
  description = "Additional tags applied to all resources"
  type        = map(string)
  default     = {}
}
