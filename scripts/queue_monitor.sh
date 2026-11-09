#!/usr/bin/env bash
# Samples the queue every INTERVAL s (default 5) into results/queue_<label>.csv.
# Stops after 3 consecutive empty readings once the queue has been busy (or Ctrl+C).
set -euo pipefail
LABEL=${1:-run}; INTERVAL=${INTERVAL:-5}; REGION=${AWS_REGION:-us-west-2}
cd "$(dirname "$0")/.."
QUEUE_URL=${QUEUE_URL:-$(terraform -chdir=terraform output -raw sqs_queue_url)}
mkdir -p results; OUT="results/queue_${LABEL}.csv"
echo "epoch,elapsed_s,visible,in_flight" > "$OUT"
START=$(date +%s); SEEN=0; ZEROS=0
echo "Writing $OUT every ${INTERVAL}s (Ctrl+C to stop)"
while true; do
  read -r VIS INF < <(aws sqs get-queue-attributes --region "$REGION" --queue-url "$QUEUE_URL" \
    --attribute-names ApproximateNumberOfMessages ApproximateNumberOfMessagesNotVisible \
    --query 'Attributes.[ApproximateNumberOfMessages,ApproximateNumberOfMessagesNotVisible]' --output text)
  NOW=$(date +%s); EL=$((NOW-START))
  echo "$NOW,$EL,$VIS,$INF" >> "$OUT"
  printf "t=%5ss  visible=%7s  in_flight=%5s\n" "$EL" "$VIS" "$INF"
  if [ $((VIS+INF)) -gt 0 ]; then SEEN=1; ZEROS=0; else ZEROS=$((ZEROS+1)); fi
  if [ "$SEEN" = 1 ] && [ "$ZEROS" -ge 3 ]; then echo "Queue drained (3 empty readings) at t=${EL}s"; break; fi
  sleep "$INTERVAL"
done
