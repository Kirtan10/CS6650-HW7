# Part III: Order API -> SNS -> Lambda. No queue, no workers.

data "archive_file" "zip" {
  type        = "zip"
  source_file = var.bootstrap # built by scripts/build_lambda.sh
  output_path = "${path.root}/build/lambda.zip"
}

resource "aws_cloudwatch_log_group" "this" {
  name              = "/aws/lambda/${var.function_name}"
  retention_in_days = 7
}

resource "aws_lambda_function" "this" {
  function_name    = var.function_name
  role             = var.role_arn
  runtime          = "provided.al2" # custom runtime: the zip holds a binary called "bootstrap"
  handler          = "bootstrap"
  architectures    = ["x86_64"]
  memory_size      = 512
  timeout          = 10 # 3 s of work + headroom
  filename         = data.archive_file.zip.output_path
  source_code_hash = data.archive_file.zip.output_base64sha256
  depends_on       = [aws_cloudwatch_log_group.this]
}

resource "aws_lambda_permission" "sns" {
  statement_id  = "AllowSNSInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.this.function_name
  principal     = "sns.amazonaws.com"
  source_arn    = var.topic_arn
}

# !! The only resource that connects Locust traffic to Lambda. Keep
# lambda_subscribed=false during every load test.
resource "aws_sns_topic_subscription" "lambda" {
  count      = var.subscribed ? 1 : 0
  topic_arn  = var.topic_arn
  protocol   = "lambda"
  endpoint   = aws_lambda_function.this.arn
  depends_on = [aws_lambda_permission.sns]
}
