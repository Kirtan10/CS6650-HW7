# One Fargate service = log group + task definition + service.
# Standard task settings for every service: 256 CPU, 512 MB, /health check.

resource "aws_cloudwatch_log_group" "this" {
  name              = "/ecs/${var.name}"
  retention_in_days = var.log_retention_days
}

resource "aws_ecs_task_definition" "this" {
  family                   = var.name
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = var.role_arn # pulls the image, writes logs
  task_role_arn            = var.role_arn # what the app's AWS SDK calls run as (SNS/SQS)

  container_definitions = jsonencode([{
    name         = var.name
    image        = var.image
    essential    = true
    portMappings = [{ containerPort = 8080, protocol = "tcp" }]
    environment  = [for k, v in var.environment : { name = k, value = v }]

    # Container-level health check (works for the processor too, which has no ALB).
    healthCheck = {
      command     = ["CMD-SHELL", "wget -qO- http://localhost:8080/health || exit 1"]
      interval    = 30
      timeout     = 5
      retries     = 3
      startPeriod = 10
    }

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.this.name
        "awslogs-region"        = var.region
        "awslogs-stream-prefix" = "ecs"
      }
    }
  }])
}

resource "aws_ecs_service" "this" {
  name            = var.name
  cluster         = var.cluster_id
  task_definition = aws_ecs_task_definition.this.arn
  desired_count   = 1 # the assignment fixes both services at 1 task
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.subnet_ids
    security_groups  = var.security_group_ids
    assign_public_ip = false # private subnets; outbound goes through the NAT
  }

  dynamic "load_balancer" {
    for_each = var.target_group_arn == null ? [] : [var.target_group_arn]
    content {
      target_group_arn = load_balancer.value
      container_name   = var.name
      container_port   = 8080
    }
  }

  health_check_grace_period_seconds = var.target_group_arn == null ? null : 60

  # `terraform apply` returns only once the new task is running and healthy,
  # so a Phase 5 run never starts against the previous worker count.
  wait_for_steady_state = true
}
