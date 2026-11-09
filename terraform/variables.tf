variable "aws_region" {
  type    = string
  default = "us-west-2"
}

variable "project" {
  description = "Prefix for every resource name"
  type        = string
  default     = "hw7"
}

variable "log_retention_days" {
  type    = number
  default = 7
}

# ---- Phase 1/2: the sync bottleneck ----
variable "payment_slots" {
  description = "Concurrent payment verifications for /orders/sync (1 = 1 order per 3 s)"
  type        = number
  default     = 1
}

# ---- Phase 3-5: the async workers (change with -var, then apply) ----
variable "processor_workers" {
  description = "Worker goroutines in the single Order Processor task (Phase 5: 1, 5, 20, 100, ...)"
  type        = number
  default     = 1
}

variable "processor_pollers" {
  description = "Concurrent ReceiveMessage loops; 0 = automatic (workers/20, between 1 and 10)"
  type        = number
  default     = 0
}

# ---- Part III: Lambda ----
# Load-testing rule: lambda_subscribed MUST be false whenever Locust runs.
variable "enable_lambda" {
  description = "Deploy the Lambda function (needs scripts/build_lambda.sh to have run)"
  type        = bool
  default     = false
}

variable "lambda_subscribed" {
  description = "Subscribe the Lambda to the SNS topic. Only true for the 5-10 curl orders in Part III."
  type        = bool
  default     = false
}
