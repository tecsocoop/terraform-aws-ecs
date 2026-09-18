######## CLUSTER

resource "aws_ecs_cluster" "main" {
  name = var.name

  setting {
    name  = "containerInsights"
    value = "disabled"
  }

  tags = merge(
    var.tags,
    {
      "Cluster" = var.name
    },
  )
}

######## CAPACITY PROVIDER (EC2 + Fargate)

resource "aws_ecs_capacity_provider" "ec2" {
  for_each = var.capacity_providers

  name = "${var.name}-${each.value.suffix}-ec2"

  auto_scaling_group_provider {
    auto_scaling_group_arn         = aws_autoscaling_group.ecs_instances[each.key].arn
    managed_termination_protection = "ENABLED"

    managed_scaling {
      status                    = "ENABLED"
      target_capacity           = 100
      minimum_scaling_step_size = 1
      maximum_scaling_step_size = 1
    }
  }

  tags = merge(
    var.tags,
    {
      "Cluster" = var.name
    },
  )
}

resource "aws_ecs_cluster_capacity_providers" "main" {
  cluster_name = aws_ecs_cluster.main.name

  capacity_providers = concat(
    ["FARGATE", "FARGATE_SPOT"],
    [for capacity_provider in aws_ecs_capacity_provider.ec2 : capacity_provider.name],
  )
}

######## SECURITY GROUP

resource "aws_security_group" "ecs_instances" {
  name        = "${var.name}-instance-sg"
  description = "Security group for ECS container instances"
  vpc_id      = var.vpc_id

  tags = merge(
    var.tags,
    {
      "Cluster" = var.name
    },
  )

  # AWS does not allow updating the description of an existing security group —
  # any change forces replacement. ignore_changes prevents this when upgrading
  # from older module versions that had a different description.
  lifecycle {
    create_before_destroy = true
    ignore_changes        = [description]
  }
}

# Bridge mode assigns a dynamic host port to each ECS task; the ALB (created
# outside this module) reaches container instances on the full ephemeral range.
resource "aws_vpc_security_group_ingress_rule" "from_alb" {
  security_group_id            = aws_security_group.ecs_instances.id
  referenced_security_group_id = var.alb_security_group_id
  description                  = "ALB to ECS tasks on dynamic host ports"
  from_port                    = 32768
  to_port                      = 65535
  ip_protocol                  = "tcp"
  tags                         = var.tags
}

resource "aws_vpc_security_group_egress_rule" "default" {
  security_group_id = aws_security_group.ecs_instances.id
  description       = "Default egress (ECR pull, CloudWatch, SSM for ECS Exec)"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
  tags              = var.tags
}

######## IAM

resource "aws_iam_role" "ecs_instance" {
  name = "${var.name}-ecs-instance-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })

  tags = merge(
    var.tags,
    {
      "Cluster" = var.name
    },
  )
}

resource "aws_iam_role_policy_attachment" "ecs_instance" {
  role       = aws_iam_role.ecs_instance.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
}

# Allows Session Manager access to the instance (separate from ECS Exec, which
# acts on the task role and works even without this policy).
resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.ecs_instance.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ecs_instance" {
  name = "${var.name}-ecs-instance-profile"
  role = aws_iam_role.ecs_instance.name
  tags = var.tags
}

######## LAUNCH TEMPLATE / AUTO SCALING GROUP

data "aws_ssm_parameter" "ecs_ami" {
  # Latest ECS-optimized Amazon Linux 2023 AMI, maintained by AWS.
  # https://docs.aws.amazon.com/AmazonECS/latest/developerguide/ecs-optimized_AMI.html
  name = "/aws/service/ecs/optimized-ami/amazon-linux-2023/recommended/image_id"
}

resource "aws_launch_template" "ecs_instance" {
  for_each      = var.capacity_providers
  name_prefix   = "${var.name}-${each.value.suffix}-ecs-"
  image_id      = data.aws_ssm_parameter.ecs_ami.value
  instance_type = each.value.instance_type
  key_name      = var.ssh_key_name

  iam_instance_profile {
    arn = aws_iam_instance_profile.ecs_instance.arn
  }

  vpc_security_group_ids = [aws_security_group.ecs_instances.id]

  user_data = base64encode(<<-EOF
    #!/bin/bash
    echo "ECS_CLUSTER=${var.name}" >> /etc/ecs/ecs.config
    echo "ECS_ENABLE_CONTAINER_METADATA=true" >> /etc/ecs/ecs.config
  EOF
  )

  tag_specifications {
    resource_type = "instance"
    tags = merge(
      var.tags,
      {
        "Cluster" = var.name
        "Name"    = "${var.name}-${each.value.suffix}-ecs-instance"
      },
    )
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "ecs_instances" {
  for_each            = var.capacity_providers
  name_prefix         = "${var.name}-${each.value.suffix}-ecs-"
  vpc_zone_identifier = var.subnets_ids
  min_size            = each.value.min_size
  max_size            = each.value.max_size
  desired_capacity    = each.value.desired_capacity

  # Required so the capacity provider can drain tasks before terminating an
  # instance.
  protect_from_scale_in = true

  launch_template {
    id      = aws_launch_template.ecs_instance[each.key].id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "${var.name}-${each.value.suffix}-ecs-instance"
    propagate_at_launch = true
  }

  dynamic "tag" {
    for_each = merge(var.tags, { "Cluster" = var.name })
    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }

  lifecycle {
    create_before_destroy = true
    ignore_changes        = [tag]
  }
}
