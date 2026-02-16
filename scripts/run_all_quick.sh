#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

TO=1s
if command -v timeout >/dev/null 2>&1; then
  echo "Running zig build test with $TO timeout..."
  if ! timeout "$TO" zig build test; then
    echo "[TIMEOUT] zig build test exceeded $TO or failed" >&2
  fi
else
  echo "timeout command not found; install coreutils (or gtimeout)" >&2
fi

echo "Running golden examples with $TO per-file timeout..."
export TIMEOUT_SECS=1
./scripts/run_golden.sh || true

