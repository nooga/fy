#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

if ! command -v timeout >/dev/null 2>&1; then
  echo "timeout not found; install coreutils or use gtimeout" >&2
  exit 1
fi

echo "Building signed fy (macOS codesign default if applicable)..."
zig build >/dev/null

fail=0
for f in examples/golden/*.fy; do
  echo "==> $f"
  TO=${TIMEOUT_SECS:-10}s
  if ! timeout "$TO" ./zig-out/bin/fy "$f"; then
    echo "[FAIL] $f (exit=$?)"
    fail=$((fail+1))
  fi
done

if [ "$fail" -gt 0 ]; then
  echo "Golden run finished with $fail failures" >&2
  exit 1
else
  echo "Golden run passed"
fi
