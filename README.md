# CS6650 Homework 7: Sync vs Async vs Serverless order processing

Kirtan Patel · Building Scalable Distributed Systems

```
Phase 1  Customer -> ALB -> Receiver --(3 s payment, limited slots)--> 200 OK
Phase 3  Customer -> ALB -> Receiver -> SNS -> SQS -> Processor (N workers) -> payment
                                     \-> 202 Accepted (< 100 ms)
Part III                          SNS -> Lambda (no queue, no workers)
```

| Path | What it is |
|---|---|
| `src/receiver/` | Go API: `GET /health`, `POST /orders/sync`, `POST /orders/async` |
| `src/processor/` | Go SQS consumer; `WORKERS` = concurrent payment verifications |
| `src/lambda/` | Go Lambda (`provided.al2`) subscribed to the same SNS topic |
| `terraform/` | VPC (10.0.0.0/16, 2 public + 2 private subnets, NAT), ALB, ECS cluster + 2 services, SNS, SQS, Lambda, CloudWatch dashboard |
| `locust/` | `ENDPOINT=sync\|async`, `TEST=normal\|flash` shapes |
| `scripts/` | Lambda build, queue monitor + plot, purge, curl test orders, cold-start report, cost calculator |

## Design notes worth explaining in the interview

- **The sync bottleneck is a semaphore, not a sleep.** `time.Sleep` parks the goroutine and frees the thread, so sleep alone would let every request "verify" in parallel. A buffered channel of capacity `PAYMENT_SLOTS` (default 1) caps concurrent verifications, so the endpoint really is limited to `slots / 3 s`.
- **Requests that wait too long fail.** Queued sync requests wait for a slot. After 60 s the ALB gives up and returns **504**, and the handler notices the cancelled context and leaves the line.
- **The processor reserves worker slots before calling ReceiveMessage.** It never holds more messages than it can start immediately. Otherwise, with 1 worker, a batch of 10 would take 30 s, exactly the visibility timeout, and SQS would redeliver the tail of the batch.
- **Messages are deleted only after processing (at-least-once delivery).** If a task dies mid-payment, the message reappears after 30 s. A real payment system would therefore need idempotency, deduplicating on `order_id`.
- **The SQS subscription uses `raw_message_delivery`.** The queue gets plain order JSON, not the SNS envelope. Lambda always gets the envelope (`Records[].Sns.Message`).
- **Private subnets reach AWS through a NAT gateway.** ECS tasks have no public IP, so ECR pulls and the SNS/SQS/Logs calls go out through the NAT. One NAT keeps the lab cheap; production would use one per AZ, or VPC endpoints.
- **Images are tagged with a hash of their source folder.** Any code change produces a new task definition, so ECS redeploys automatically. No more forcing a rebuild of a stale `:latest`.

## 0. Deploy (≈ 5 min)

```bash
cd ~/Desktop/CS6650-BSDS/hw07/terraform
unset AWS_REGION
export DOCKER_HOST=$(docker context inspect --format '{{.Endpoints.docker.Host}}')
terraform init
terraform apply                    # ~30 resources; the NAT gateway takes 1-2 min
ALB=$(terraform output -raw alb_url)
curl $ALB/health                   # 503 for ~1 min until the target is healthy, then {"status":"ok"}
curl -s -X POST $ALB/orders/async -H 'Content-Type: application/json' \
  -d '{"customer_id":1,"items":[{"product_id":"SKU-0001","quantity":1,"price":9.99}]}'
```

Open the `dashboard_url` output. Every screenshot the report needs is on that one dashboard.

**Changing a setting:** edit `terraform/terraform.tfvars`, then `terraform apply`. The apply waits until the new task is healthy (`wait_for_steady_state`), so when it returns, the setting is live.

## Phase 1: synchronous (payment_slots = 1)

```bash
cd ../locust
ENDPOINT=sync TEST=normal docker compose up     # Host = $ALB, Start; stops after 30 s
ENDPOINT=sync TEST=flash  docker compose up     # 20 users, 60 s
```

Record for each run: requests, failures, RPS, median/p95/max latency (Locust **Statistics** tab and `locust/results/*.csv`), plus the ALB widget showing 5xx. Expect 100% success at normal load, but with latencies far above 3 s, because orders wait in line. Under the flash sale, expect ~20 completed orders per minute, latencies climbing toward 60 s, and 504s.

## Phases 3–4: async with 1 worker

Make sure `lambda_subscribed = false`.

Terminal A:
```bash
./scripts/queue_monitor.sh workers_1
```

Terminal B:
```bash
cd locust && ENDPOINT=async TEST=flash docker compose up
```

Expect ~100% 202s at roughly 55–60 RPS with latency under 100 ms. The queue climbs to about 3,000–3,500.

**Don't wait for it to drain:** at 0.33/s that takes about 3 hours. Watch it for ~5 minutes to measure the drain slope, take the CloudWatch screenshot, then press Ctrl+C and run `./scripts/purge_queue.sh`.

## Phase 5: scale workers

For each W in 5, 20, 100, and finally 180 or 200:

1. Set `processor_workers = W` in `terraform.tfvars` and run `terraform apply`.
2. Run `./scripts/purge_queue.sh` and wait 60 s.
3. Start `./scripts/queue_monitor.sh workers_W` (Terminal A), then the async flash test (Terminal B).
4. Record peak depth, time back to 0 (the monitor stops itself), the processor's `rate_per_s` log line, and CPU/memory from the dashboard.

Then:

```bash
python3 scripts/plot_queue.py results/queue_workers_*.csv     # overlay chart + table
aws logs tail /ecs/hw7-processor --since 10m --region us-west-2 | grep stats
```

At W=5 the drain takes ~35 min: measure 10 min of slope and extrapolate. Expect CPU to stay at a few percent even with 200 workers, since sleeping goroutines cost almost nothing. The limit is the downstream payment rate, not the container.

## Part III: Lambda (curl only, never Locust)

```bash
./scripts/build_lambda.sh
# terraform.tfvars: enable_lambda = true, lambda_subscribed = true
cd terraform && terraform apply && cd ..
./scripts/send_test_orders.sh 5 spaced      # first order cold, the rest warm
./scripts/send_test_orders.sh 3 burst       # concurrent -> each new instance is cold
# wait ~6 min idle, then:
./scripts/send_test_orders.sh 2 spaced      # cold again after idling?
./scripts/lambda_reports.sh 30              # cold/warm table with Init Duration and overhead %
python3 scripts/cost_calc.py                # cost table + break-even
# Before ANY further Locust test: set lambda_subscribed = false and terraform apply
```

Screenshot the log stream showing REPORT lines with and without `Init Duration`.

## Tear down

```bash
cd terraform && terraform destroy
```

The NAT gateway bills about $0.045/hour even when idle, so destroy as soon as you're done.

## Fill-in-the-blank answers (theory, compare with measured)

| Question | Answer |
|---|---|
| Phase 2 max throughput | `slots / 3 s`: 0.33/s with 1 slot (our default). If each of 20 customers effectively had its own slot: 20/3 = 6.67/s |
| Phase 2 orders lost/s vs 20/s demand | ≈ 19.67/s (1 slot) or ≈ 13.3/s (20 slots) |
| Phase 4 queue growth | 60 − 0.33 ≈ 59.67 msg/s |
| Phase 4 time to clear a 1-hour backlog | (60 − 0.33) × 3600 = 214,800 msgs ÷ 0.33/s ≈ 644,400 s ≈ **10,740 min (~7.5 days)**, longer than the 4-day retention, so ~40% would expire unprocessed |
| Phase 5 rates | 5 → 1.67/s, 20 → 6.67/s, 100 → 33.3/s |
| Minimum workers for 60/s | 60 × 3 s = **180** (Little's Law: concurrency = arrival rate × service time); run ~200 for headroom |
| Lambda break-even vs $17 | ≈ **947K orders/month** (the assignment says ~1.7M; at 1.7M Lambda actually costs ≈ $36) |
