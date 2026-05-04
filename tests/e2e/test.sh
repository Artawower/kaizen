#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/../.."
docker build -t kaizen-e2e -f tests/e2e/Dockerfile .
docker run --rm kaizen-e2e
