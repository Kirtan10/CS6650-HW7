# One dashboard for every screenshot the report needs.

locals {
  q   = module.messaging.queue_name
  lb  = module.alb.lb_arn_suffix
  tg  = module.alb.target_group_arn_suffix
  cl  = aws_ecs_cluster.this.name
  rx  = module.receiver.service_name
  px  = module.processor.service_name
  fn  = "${var.project}-order-lambda"
  reg = var.aws_region
}

resource "aws_cloudwatch_dashboard" "hw7" {
  dashboard_name = "${var.project}-orders"
  dashboard_body = jsonencode({
    widgets = [
      {
        type = "metric", x = 0, y = 0, width = 12, height = 7
        properties = {
          title  = "SQS queue depth: ApproximateNumberOfMessagesVisible (spike + drain)"
          region = local.reg, view = "timeSeries", period = 60, stat = "Maximum"
          metrics = [
            ["AWS/SQS", "ApproximateNumberOfMessagesVisible", "QueueName", local.q, { label = "Visible (waiting)" }],
            ["AWS/SQS", "ApproximateNumberOfMessagesNotVisible", "QueueName", local.q, { label = "In flight (being processed)" }],
          ]
        }
      },
      {
        type = "metric", x = 12, y = 0, width = 12, height = 7
        properties = {
          title  = "Arrival vs processing: messages sent vs deleted per minute"
          region = local.reg, view = "timeSeries", period = 60, stat = "Sum"
          metrics = [
            ["AWS/SQS", "NumberOfMessagesSent", "QueueName", local.q, { label = "Sent (accepted orders)" }],
            ["AWS/SQS", "NumberOfMessagesDeleted", "QueueName", local.q, { label = "Deleted (processed orders)" }],
          ]
        }
      },
      {
        type = "metric", x = 0, y = 7, width = 12, height = 6
        properties = {
          title  = "Age of oldest message (s): how late is the slowest order confirmation?"
          region = local.reg, view = "timeSeries", period = 60, stat = "Maximum"
          metrics = [
            ["AWS/SQS", "ApproximateAgeOfOldestMessage", "QueueName", local.q],
          ]
        }
      },
      {
        type = "metric", x = 12, y = 7, width = 12, height = 6
        properties = {
          title  = "ECS CPU / memory % (resource utilization)"
          region = local.reg, view = "timeSeries", period = 60, stat = "Maximum"
          metrics = [
            ["AWS/ECS", "CPUUtilization", "ClusterName", local.cl, "ServiceName", local.px, { label = "processor CPU" }],
            ["AWS/ECS", "MemoryUtilization", "ClusterName", local.cl, "ServiceName", local.px, { label = "processor memory" }],
            ["AWS/ECS", "CPUUtilization", "ClusterName", local.cl, "ServiceName", local.rx, { label = "receiver CPU" }],
            ["AWS/ECS", "MemoryUtilization", "ClusterName", local.cl, "ServiceName", local.rx, { label = "receiver memory" }],
          ]
          yAxis = { left = { min = 0, max = 100 } }
        }
      },
      {
        type = "metric", x = 0, y = 13, width = 12, height = 6
        properties = {
          title  = "ALB: requests and errors per minute (504 = sync customer gave up)"
          region = local.reg, view = "timeSeries", period = 60, stat = "Sum"
          metrics = [
            ["AWS/ApplicationELB", "RequestCount", "LoadBalancer", local.lb, { label = "requests" }],
            ["AWS/ApplicationELB", "HTTPCode_Target_2XX_Count", "LoadBalancer", local.lb, { label = "2xx" }],
            ["AWS/ApplicationELB", "HTTPCode_ELB_5XX_Count", "LoadBalancer", local.lb, { label = "5xx from ALB (502/503/504)" }],
            ["AWS/ApplicationELB", "HTTPCode_Target_5XX_Count", "LoadBalancer", local.lb, { label = "5xx from receiver" }],
          ]
        }
      },
      {
        type = "metric", x = 12, y = 13, width = 12, height = 6
        properties = {
          title  = "ALB target response time (s)"
          region = local.reg, view = "timeSeries", period = 60
          metrics = [
            ["AWS/ApplicationELB", "TargetResponseTime", "LoadBalancer", local.lb, { stat = "Average", label = "average" }],
            ["AWS/ApplicationELB", "TargetResponseTime", "LoadBalancer", local.lb, { stat = "p99", label = "p99" }],
          ]
        }
      },
      {
        type = "metric", x = 0, y = 19, width = 24, height = 6
        properties = {
          title  = "Part III Lambda: invocations, errors, concurrency, duration"
          region = local.reg, view = "timeSeries", period = 60
          metrics = [
            ["AWS/Lambda", "Invocations", "FunctionName", local.fn, { stat = "Sum" }],
            ["AWS/Lambda", "Errors", "FunctionName", local.fn, { stat = "Sum" }],
            ["AWS/Lambda", "ConcurrentExecutions", "FunctionName", local.fn, { stat = "Maximum" }],
            ["AWS/Lambda", "Duration", "FunctionName", local.fn, { stat = "Maximum", yAxis = "right" }],
          ]
        }
      },
    ]
  })
}
