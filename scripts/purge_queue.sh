#!/usr/bin/env bash
# Empty the queue between runs so each Phase 5 test starts from zero.
# (SQS allows one purge per 60 s; it can take up to a minute to finish.)
set -euo pipefail
cd "$(dirname "$0")/.."
QUEUE_URL=$(terraform -chdir=terraform output -raw sqs_queue_url)
aws sqs purge-queue --region "${AWS_REGION:-us-west-2}" --queue-url "$QUEUE_URL"
echo "Purge requested. Wait ~60 s before the next test."
