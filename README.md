# terraform-aws-ecs

Terraform module that deploys an Amazon ECS cluster with an EC2 capacity
provider (plus `FARGATE` / `FARGATE_SPOT`), backed by an Auto Scaling Group of
ECS-optimized container instances. It creates the cluster, the capacity
providers, the container instances security group, the instance IAM role /
instance profile, the launch template and the ASG.

> [!important]
> This module does **not** create an Application Load Balancer. It is designed
> to expose services through an **ALB created previously** (outside this
> module, e.g. directly in the environment root). The module only opens the
> container instances security group to receive traffic from the ALB's
> security group (`alb_security_group_id`). Target groups, listeners, listener
> rules, the ECS task definition and the ECS service must be declared in the
> root module — see the [example](#example-ecs-service--task-definition) at
> the end of this document.

Designed to be used together with the `terraform-aws-vpc` module, consuming
its outputs (`vpc_id`, `private_subnet_ids_list`), and an ALB security group
created beforehand.

## Requirements

| Name      | Version   |
|-----------|-----------|
| terraform | >= 1.3.7  |
| aws       | >= 5.9.0  |

## Usage

Published on the [public Terraform Registry](https://registry.terraform.io/)
under the `tecsocoop` namespace.

```hcl
module "ecs" {
  source  = "tecsocoop/ecs/aws"
#  version = "X.X.X" # see the latest available tag

  name = "uat-example"

  vpc_id      = module.vpc.vpc_id
  subnets_ids = module.vpc.private_subnet_ids_list

  # Security group of the pre-existing ALB
  alb_security_group_id = aws_security_group.alb.id

  instance_type = "t3a.medium"

  asg_min_size         = 1
  asg_max_size         = 1
  asg_desired_capacity = 1

  tags = {
    "Environment" = "uat"
  }
}
```

> [!note]
> Container instances run in **bridge** network mode: each task gets a
> dynamic host port in the `32768-65535` range. The module's security group
> only allows that range from `alb_security_group_id`; the ALB target groups
> must use `target_type = "instance"` and the dynamic port assigned by ECS.

> [!note]
> The `aws_ecs_capacity_provider` `managed_termination_protection = "ENABLED"`
> together with `protect_from_scale_in = true` on the ASG lets ECS drain tasks
> from an instance before the ASG terminates it during scale-in.

### Node access via SSM Session Manager

Container instances get the `AmazonSSMManagedInstanceCore` policy and the SSM
agent is preinstalled on the ECS-optimized AMI, so they are reachable via AWS
Systems Manager Session Manager without an SSH key (`ssh_key_name` is
optional). This is separate from **ECS Exec**, which runs against the task
role/container and works independently of instance-level SSM access.

```bash
aws ssm start-session --target <instance_id>
```

<details>
<summary>Variables</summary>

| Variable                 | Description                                                                        | Values                     | Default |
|---------------------------|-------------------------------------------------------------------------------------|----------------------------|---------|
| `name`                    | Cluster name.                                                                        | string - e.g. `uat-example` | -       |
| `vpc_id`                  | VPC ID where the ASG will be deployed.                                              | string                     | -       |
| `subnets_ids`             | Private subnet IDs for the ASG.                                                     | `list(string)`             | -       |
| `alb_security_group_id`   | Security group ID of the pre-existing ALB allowed to reach ECS container instances on their dynamic host ports. | string | -       |
| `instance_type`           | Instance type for the ECS container instances ASG.                                 | string - e.g. `t3a.medium` | -       |
| `ssh_key_name`            | AWS key pair name for SSH access (optional; instances are reachable via SSM).      | string                     | `null`  |
| `asg_min_size`            | Minimum number of ECS container instances in the ASG.                              | number                     | `1`     |
| `asg_max_size`            | Maximum number of ECS container instances in the ASG.                              | number                     | `1`     |
| `asg_desired_capacity`    | Desired number of ECS container instances in the ASG.                              | number                     | `1`     |
| `tags`                    | Additional tags applied to all resources.                                          | `map(string)`              | `{}`    |

</details>

<details>
<summary>Outputs</summary>

| Output                             | Description                                                              |
|-------------------------------------|---------------------------------------------------------------------------|
| `cluster_name`                      | Name of the ECS cluster.                                                 |
| `cluster_arn`                       | ARN of the ECS cluster.                                                  |
| `capacity_provider_name`            | Name of the ECS EC2 capacity provider (used in `capacity_provider_strategy` blocks). |
| `ecs_instances_security_group_id`   | Security group attached to ECS container instances.                     |
| `ecs_instance_role_arn`             | ARN of the IAM role assumed by ECS container instances (EC2).           |
| `ecs_instance_role_name`            | Name of the IAM role assumed by ECS container instances (EC2).          |
| `autoscaling_group_arn`             | ARN of the ECS container instances Auto Scaling Group.                  |

</details>

## Example: ECS service + task definition

The following is a full example of an `aws_ecs_task_definition` /
`aws_ecs_service` pair, declared in the root module alongside `module "ecs"`,
together with the ALB target groups / listener rules and the task execution
IAM role. **All values are illustrative** — replace names, domains, images,
database endpoints and secrets with real ones. Container images point to
public test images (`redis`, `hashicorp/http-echo`, `traefik/whoami`) so the
snippet is runnable as-is for a smoke test.

> [!warning]
> Never hardcode real credentials (passwords, access keys, private keys) in
> `environment` blocks. Inject them at task startup with the `secrets` block
> pointing to AWS Secrets Manager / SSM Parameter Store, and grant
> `secretsmanager:GetSecretValue` only on the specific secret ARNs via the
> task execution role, as shown below.

```hcl
resource "aws_ecs_task_definition" "app" {
  family                   = "uat-example-app"
  requires_compatibilities = ["EC2"]
  network_mode             = "bridge"
  cpu                      = "1024"
  memory                   = "1536"
  execution_role_arn       = aws_iam_role.task_execution.arn

  container_definitions = jsonencode([
    {
      name      = "redis"
      image     = "redis:8.0.2-alpine"
      essential = true
      cpu       = 256
      memory    = 512

      portMappings = [
        {
          containerPort = 6379
          hostPort      = 0 # dynamic host port, bridge mode
          protocol      = "tcp"
        }
      ]
    },
    {
      name      = "backend"
      image     = "hashicorp/http-echo" # replace with the real application image
      essential = true
      cpu       = 256
      memory    = 512

      portMappings = [
        {
          containerPort = 5678
          hostPort      = 0 # dynamic host port, bridge mode
          protocol      = "tcp"
        }
      ]

      environment = [
        { name = "APP_ENVIRONMENT", value = "uat" },
        { name = "APP_PORT", value = "5678" },
        { name = "REDIS_HOST", value = "redis" },
        { name = "DB_HOST", value = "example-db.xxxxxxxxxxxx.us-east-1.rds.amazonaws.com" },
        { name = "DB_PORT", value = "5432" },
        { name = "DB_NAME", value = "example_app" },
        { name = "DB_USER", value = "example_app" },
        { name = "LOG_LEVEL", value = "DEBUG" },
      ]

      secrets = [
        { name = "DB_PASSWORD", valueFrom = "arn:aws:secretsmanager:us-east-1:ACCOUNT_ID:secret:uat/example-app/db-password" },
      ]
    },
    {
      name      = "auth"
      image     = "traefik/whoami" # replace with the real auth service image
      essential = true
      cpu       = 256
      memory    = 512

      portMappings = [
        {
          containerPort = 80
          hostPort      = 0 # dynamic host port, no conflict with the other containers
          protocol      = "tcp"
        }
      ]

      environment = [
        { name = "AUTH_ENVIRONMENT", value = "uat" },
        { name = "AUTH_PORT", value = "80" },
        { name = "REDIS_HOST", value = "redis" },
        { name = "AUTH_DB_HOST", value = "example-db.xxxxxxxxxxxx.us-east-1.rds.amazonaws.com" },
        { name = "AUTH_DB_NAME", value = "example_auth" },
        { name = "AUTH_DB_USER", value = "example_auth" },
        { name = "AUTH_TOKEN_EXPIRATION", value = "3600" },
      ]

      secrets = [
        { name = "AUTH_DB_PASSWORD", valueFrom = "arn:aws:secretsmanager:us-east-1:ACCOUNT_ID:secret:uat/example-app/auth-db-password" },
        { name = "AUTH_REFRESH_SECRET", valueFrom = "arn:aws:secretsmanager:us-east-1:ACCOUNT_ID:secret:uat/example-app/auth-refresh-secret" },
        { name = "JWK_RSAKEY", valueFrom = "arn:aws:secretsmanager:us-east-1:ACCOUNT_ID:secret:uat/example-app/jwk-rsa-key" },
      ]
    }
  ])
}

resource "aws_ecs_service" "app" {
  name            = "uat-example-app"
  cluster         = module.ecs.cluster_name
  task_definition = aws_ecs_task_definition.app.arn
  desired_count   = 1

  force_new_deployment = true

  capacity_provider_strategy {
    capacity_provider = module.ecs.capacity_provider_name
    base              = 1
    weight            = 100
  }

  # Single instance: no room for a second task copy during deploys.
  deployment_minimum_healthy_percent = 0
  deployment_maximum_percent         = 100

  load_balancer {
    target_group_arn = aws_lb_target_group.backend.arn
    container_name   = "backend"
    container_port   = 5678
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.auth.arn
    container_name   = "auth"
    container_port   = 80
  }

  depends_on = [aws_lb_listener.https]
}

################################# ALB TARGET GROUPS
# One target group per application allows independent health checks and
# deployments. aws_lb_listener.https is assumed to already exist (created
# with the pre-existing ALB).

resource "aws_lb_target_group" "backend" {
  name                 = "uat-example-backend"
  port                 = 5678
  protocol             = "HTTP"
  target_type          = "instance"
  vpc_id               = module.vpc.vpc_id
  deregistration_delay = 30

  health_check {
    path                = "/"
    protocol            = "HTTP"
    matcher             = "200-399"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }
}

resource "aws_lb_listener_rule" "backend" {
  listener_arn = aws_lb_listener.https.arn
  priority     = 100

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.backend.arn
  }

  condition {
    host_header {
      values = ["api.uat.example.com"]
    }
  }
}

resource "aws_lb_target_group" "auth" {
  name                 = "uat-example-auth"
  port                 = 80
  protocol             = "HTTP"
  target_type          = "instance"
  vpc_id               = module.vpc.vpc_id
  deregistration_delay = 30

  health_check {
    path                = "/"
    protocol            = "HTTP"
    matcher             = "200-399"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }
}

resource "aws_lb_listener_rule" "auth" {
  listener_arn = aws_lb_listener.https.arn
  priority     = 110

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.auth.arn
  }

  condition {
    host_header {
      values = ["auth.uat.example.com"]
    }
  }
}

############## IAM

# Role assumed by ECS to pull images, write logs, and inject secrets at task startup.
resource "aws_iam_role" "task_execution" {
  name = "uat-example-app-task-execution"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "task_execution_managed" {
  role       = aws_iam_role.task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy" # ECR + CloudWatch
}

# Read access limited to the secrets injected into this task at startup.
resource "aws_iam_role_policy" "task_execution_secrets" {
  name = "uat-example-app-execution-secrets"
  role = aws_iam_role.task_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "ReadInjectedSecrets"
      Effect   = "Allow"
      Action   = ["secretsmanager:GetSecretValue"]
      Resource = ["arn:aws:secretsmanager:us-east-1:ACCOUNT_ID:secret:uat/example-app-*"]
    }]
  })
}
```

## License

Licensed under the [Apache License 2.0](LICENSE).
