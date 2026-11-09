output "alb_url" {
  description = "Locust host / curl base URL"
  value       = "http://${module.alb.dns_name}"
}

output "sns_topic_arn" {
  value = module.messaging.topic_arn
}

output "sqs_queue_url" {
  value = module.messaging.queue_url
}

output "sqs_queue_name" {
  value = module.messaging.queue_name
}

output "ecs_cluster" {
  value = aws_ecs_cluster.this.name
}

output "processor_workers" {
  value = var.processor_workers
}

output "lambda_log_group" {
  value = var.enable_lambda ? module.lambda[0].log_group_name : "(lambda disabled)"
}

output "lambda_subscribed" {
  description = "Must be false before any Locust test"
  value       = var.enable_lambda && var.lambda_subscribed
}

output "dashboard_url" {
  value = "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards/dashboard/${aws_cloudwatch_dashboard.hw7.dashboard_name}"
}
