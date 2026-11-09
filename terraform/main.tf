# Order API -> SNS -> SQS -> Order Processor   (Part II)
#                 \-> Lambda                    (Part III, behind two flags)

data "aws_iam_role" "lab_role" {
  name = "LabRole" # Learner Lab can't create IAM roles; reuse this one everywhere
}

module "network" {
  source  = "./modules/network"
  project = var.project
}

module "messaging" {
  source  = "./modules/messaging"
  project = var.project
}

# ---------------- Images: build linux/amd64 and push to ECR ----------------
locals {
  services = toset(["receiver", "processor"])
  # Content hash of each service's source folder: any code change -> new tag
  # -> new task definition -> ECS redeploys. (No more stale :latest.)
  src_hash = {
    for s in local.services : s => sha1(join("", [
      for f in sort(fileset("${path.root}/../src/${s}", "**")) :
      filesha1("${path.root}/../src/${s}/${f}")
    ]))
  }
}

module "ecr" {
  for_each        = local.services
  source          = "./modules/ecr"
  repository_name = "${var.project}-${each.key}"
}

resource "docker_image" "app" {
  for_each = local.services
  name     = "${module.ecr[each.key].repository_url}:${substr(local.src_hash[each.key], 0, 12)}"
  build {
    context  = "${path.root}/../src/${each.key}"
    platform = "linux/amd64" # Fargate is x86_64; an M-series Mac would build ARM otherwise
  }
  triggers = { src = local.src_hash[each.key] }
}

resource "docker_registry_image" "app" {
  for_each      = local.services
  name          = docker_image.app[each.key].name
  keep_remotely = true
  triggers      = { src = local.src_hash[each.key] }
}

# ---------------- ALB (public subnets) ----------------
module "alb" {
  source            = "./modules/alb"
  project           = var.project
  vpc_id            = module.network.vpc_id
  public_subnet_ids = module.network.public_subnet_ids
  container_port    = 8080
}

# ---------------- ECS (private subnets) ----------------
resource "aws_ecs_cluster" "this" {
  name = "${var.project}-cluster"
  setting {
    name  = "containerInsights"
    value = "enabled" # per-service CPU/memory for the "resource utilization" question
  }
}

# Receiver: reachable only from the ALB.
resource "aws_security_group" "receiver" {
  name   = "${var.project}-receiver-sg"
  vpc_id = module.network.vpc_id
  ingress {
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [module.alb.security_group_id]
    description     = "HTTP from the ALB only"
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "SNS, ECR, CloudWatch via the NAT gateway"
  }
}

# Processor: nothing calls it; it only makes outbound calls to SQS.
resource "aws_security_group" "processor" {
  name   = "${var.project}-processor-sg"
  vpc_id = module.network.vpc_id
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "SQS, ECR, CloudWatch via the NAT gateway"
  }
}

module "receiver" {
  source             = "./modules/ecs_service"
  name               = "${var.project}-receiver"
  cluster_id         = aws_ecs_cluster.this.id
  image              = docker_registry_image.app["receiver"].name
  subnet_ids         = module.network.private_subnet_ids
  security_group_ids = [aws_security_group.receiver.id]
  role_arn           = data.aws_iam_role.lab_role.arn
  region             = var.aws_region
  log_retention_days = var.log_retention_days
  target_group_arn   = module.alb.target_group_arn
  environment = {
    SNS_TOPIC_ARN = module.messaging.topic_arn
    PAYMENT_SLOTS = tostring(var.payment_slots)
  }
  depends_on = [module.alb] # the target group needs its listener first
}

module "processor" {
  source             = "./modules/ecs_service"
  name               = "${var.project}-processor"
  cluster_id         = aws_ecs_cluster.this.id
  image              = docker_registry_image.app["processor"].name
  subnet_ids         = module.network.private_subnet_ids
  security_group_ids = [aws_security_group.processor.id]
  role_arn           = data.aws_iam_role.lab_role.arn
  region             = var.aws_region
  log_retention_days = var.log_retention_days
  target_group_arn   = null
  environment = {
    QUEUE_URL = module.messaging.queue_url
    WORKERS   = tostring(var.processor_workers)
    POLLERS   = var.processor_pollers > 0 ? tostring(var.processor_pollers) : ""
  }
}

# ---------------- Part III: Lambda subscribed to the same topic ----------------
module "lambda" {
  count         = var.enable_lambda ? 1 : 0
  source        = "./modules/lambda"
  function_name = "${var.project}-order-lambda"
  bootstrap     = "${path.root}/../src/lambda/bootstrap"
  role_arn      = data.aws_iam_role.lab_role.arn
  topic_arn     = module.messaging.topic_arn
  subscribed    = var.lambda_subscribed
}
