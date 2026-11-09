# Public ALB in the two public subnets, forwarding port 80 to the receiver.

resource "aws_security_group" "alb" {
  name        = "${var.project}-alb-sg"
  description = "HTTP from anywhere to the ALB"
  vpc_id      = var.vpc_id
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_lb" "this" {
  name               = "${var.project}-alb"
  load_balancer_type = "application"
  internal           = false
  security_groups    = [aws_security_group.alb.id]
  subnets            = var.public_subnet_ids
  # idle_timeout stays at the default 60 s: a sync request still waiting for a
  # payment slot after 60 s gets a 504 from the ALB. That IS the Phase 1 failure.
}

resource "aws_lb_target_group" "this" {
  name                 = "${var.project}-receiver-tg"
  target_type          = "ip" # Fargate/awsvpc: each task has its own IP
  protocol             = "HTTP"
  port                 = var.container_port
  vpc_id               = var.vpc_id
  deregistration_delay = 30
  health_check {
    path                = "/health"
    matcher             = "200"
    interval            = 30
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 5
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this.arn
  }
}
