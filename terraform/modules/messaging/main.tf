# SNS topic fans out to the SQS queue (and, in Part III, to the Lambda).

resource "aws_sns_topic" "orders" {
  name = "order-processing-events"
}

resource "aws_sqs_queue" "orders" {
  name                       = "order-processing-queue"
  visibility_timeout_seconds = 30     # default; a 3 s job fits easily IF we don't over-fetch
  message_retention_seconds  = 345600 # 4 days (default)
  receive_wait_time_seconds  = 20     # long polling
}

# Let this topic (and only this topic) send into the queue.
resource "aws_sqs_queue_policy" "orders" {
  queue_url = aws_sqs_queue.orders.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowSNS"
      Effect    = "Allow"
      Principal = { Service = "sns.amazonaws.com" }
      Action    = "sqs:SendMessage"
      Resource  = aws_sqs_queue.orders.arn
      Condition = { ArnEquals = { "aws:SourceArn" = aws_sns_topic.orders.arn } }
    }]
  })
}

resource "aws_sns_topic_subscription" "queue" {
  topic_arn = aws_sns_topic.orders.arn
  protocol  = "sqs"
  endpoint  = aws_sqs_queue.orders.arn
  # Deliver the order JSON as-is instead of wrapped in an SNS envelope,
  # so the processor can unmarshal the body directly.
  raw_message_delivery = true
  depends_on           = [aws_sqs_queue_policy.orders]
}
