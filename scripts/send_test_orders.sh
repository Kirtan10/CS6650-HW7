#!/usr/bin/env bash
# Part III: send a handful of orders through the async API with curl.
#
#   ./scripts/send_test_orders.sh 10 spaced   # one every GAP s (default 5): mostly warm starts
#   ./scripts/send_test_orders.sh 5 burst     # all at once: each needs its own instance -> cold starts
#
# Never more than 10. This is NOT a load test.
set -euo pipefail
N=${1:-5}; MODE=${2:-spaced}; GAP=${GAP:-5}
[ "$N" -le 10 ] || { echo "Max 10 orders (protect the account)"; exit 1; }
cd "$(dirname "$0")/.."
[ "$(terraform -chdir=terraform output -raw lambda_subscribed)" = "true" ] || \
  echo "WARNING: lambda_subscribed is false, these orders will only reach SQS."
ALB=$(terraform -chdir=terraform output -raw alb_url)
for i in $(seq 1 "$N"); do
  BODY="{\"customer_id\": $((1000 + i)), \"items\": [{\"product_id\": \"SKU-00$i\", \"quantity\": 1, \"price\": 19.99}]}"
  if [ "$MODE" = burst ]; then
    curl -s -X POST "$ALB/orders/async" -H "Content-Type: application/json" -d "$BODY" -w "  -> %{http_code} in %{time_total}s\n" &
  else
    echo "$(date +%T) order $i"
    curl -s -X POST "$ALB/orders/async" -H "Content-Type: application/json" -d "$BODY" -w "  -> %{http_code} in %{time_total}s\n"
    [ "$i" -lt "$N" ] && sleep "$GAP"
  fi
done
wait
echo "Done. Wait ~10 s, then run ./scripts/lambda_reports.sh"
