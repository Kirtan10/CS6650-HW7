# Edit these and run `terraform apply` between experiments.
# (Using this file instead of -var flags means one apply can't silently
#  undo another setting, e.g. destroy the Lambda while changing workers.)

payment_slots     = 1     # Phase 1: 1 = "1 order per 3 s"
processor_workers = 1     # Phase 3/4: 1   Phase 5: 5, 20, 100, then 180+
processor_pollers = 0     # 0 = auto

enable_lambda     = true
lambda_subscribed = false
