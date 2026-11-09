#!/usr/bin/env bash
# Builds src/lambda/bootstrap for Lambda's provided.al2 runtime (linux/amd64).
# Uses your local Go if installed, otherwise a Go Docker container.
set -euo pipefail
cd "$(dirname "$0")/../src/lambda"
BUILD='go mod tidy && CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -tags lambda.norpc -o bootstrap .'
if command -v go >/dev/null 2>&1; then
  sh -c "$BUILD"
else
  docker run --rm -v "$PWD":/src -w /src golang:1.25-alpine sh -c "$BUILD"
fi
file bootstrap 2>/dev/null || true
ls -lh bootstrap
echo "Built src/lambda/bootstrap. Next: terraform apply -var enable_lambda=true"
