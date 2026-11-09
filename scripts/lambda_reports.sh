#!/usr/bin/env bash
# Lambda REPORT lines -> cold/warm table.   ./scripts/lambda_reports.sh [minutes_back=60]
set -euo pipefail
MIN=${1:-60}; REGION=${AWS_REGION:-us-west-2}
cd "$(dirname "$0")/.."
LG=$(terraform -chdir=terraform output -raw lambda_log_group)
SINCE=$(( ($(date +%s) - MIN*60) * 1000 ))
aws logs filter-log-events --region "$REGION" --log-group-name "$LG" \
  --start-time "$SINCE" --filter-pattern '"REPORT RequestId"' --output json |
  python3 scripts/lambda_reports.py
