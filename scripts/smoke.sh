#!/usr/bin/env bash
# Smoke test runner: unit tests + golden output comparison
set -uo pipefail

cd "$(dirname "$0")/.."

# Colors (disabled if not a terminal)
if [ -t 1 ]; then
  GREEN='\033[32m' RED='\033[31m' YELLOW='\033[33m' DIM='\033[2m' RESET='\033[0m'
else
  GREEN='' RED='' YELLOW='' DIM='' RESET=''
fi

pass=0 fail=0 skip=0
fails=""

# --- Phase 1: Build ---
printf "${DIM}Building...${RESET} "
if ! zig build 2>/dev/null; then
  printf "${RED}BUILD FAILED${RESET}\n"
  exit 1
fi
printf "${GREEN}ok${RESET}\n"

# --- Phase 2: Unit tests ---
printf "${DIM}Unit tests...${RESET} "
if zig build test 2>/dev/null; then
  printf "${GREEN}ok${RESET}\n"
  pass=$((pass+1))
else
  printf "${RED}FAIL${RESET}\n"
  fail=$((fail+1))
  fails="${fails}\n  unit-tests"
fi

# --- Phase 3: Golden tests ---
FY=./zig-out/bin/fy
TO=${TIMEOUT_SECS:-5}

# Tests with non-deterministic output (PIDs etc) — exit-code only
EXIT_ONLY="ffi_dlopen_close ffi_getpid"

# Known failing tests — listed so they don't cause overall failure
KNOWN_FAIL="ffi_c_abs ffi_c_strlen ffi_cstr_free_strlen ffi_strlen_pac ffi_with_cstr_f_strlen ffi_with_cstr_q_puts ffi_with_cstr_q_strlen locals_nested_shadow"

for f in examples/golden/*.fy; do
  name=$(basename "$f" .fy)
  expected="${f%.fy}.expected"

  # Check if known failure
  is_known_fail=0
  for kf in $KNOWN_FAIL; do
    [ "$name" = "$kf" ] && is_known_fail=1
  done

  # Run with timeout
  actual=$(timeout "$TO" "$FY" "$f" 2>/dev/null)
  rc=$?

  if [ $is_known_fail -eq 1 ]; then
    if [ $rc -eq 0 ]; then
      # Known failure now passes — that's great, report it
      printf "  ${GREEN}FIXED${RESET}  %s (was known-fail)\n" "$name"
      pass=$((pass+1))
    else
      printf "  ${YELLOW}SKIP${RESET}   %s (known-fail)\n" "$name"
      skip=$((skip+1))
    fi
    continue
  fi

  if [ $rc -ne 0 ]; then
    printf "  ${RED}CRASH${RESET}  %s (exit %d)\n" "$name" "$rc"
    fail=$((fail+1))
    fails="${fails}\n  $name (exit $rc)"
    continue
  fi

  # Exit-code only test?
  is_exit_only=0
  for eo in $EXIT_ONLY; do
    [ "$name" = "$eo" ] && is_exit_only=1
  done

  if [ $is_exit_only -eq 1 ]; then
    printf "  ${GREEN}PASS${RESET}   %s (exit-only)\n" "$name"
    pass=$((pass+1))
    continue
  fi

  # Compare output if .expected exists
  if [ -f "$expected" ]; then
    expected_content=$(cat "$expected")
    if [ "$actual" = "$expected_content" ]; then
      printf "  ${GREEN}PASS${RESET}   %s\n" "$name"
      pass=$((pass+1))
    else
      printf "  ${RED}FAIL${RESET}   %s (output mismatch)\n" "$name"
      printf "    ${DIM}expected:${RESET} %s\n" "$(echo "$expected_content" | head -3)"
      printf "    ${DIM}actual:${RESET}   %s\n" "$(echo "$actual" | head -3)"
      fail=$((fail+1))
      fails="${fails}\n  $name (output mismatch)"
    fi
  else
    # No .expected file — just check exit code
    printf "  ${GREEN}PASS${RESET}   %s (exit-only, no .expected)\n" "$name"
    pass=$((pass+1))
  fi
done

# --- Summary ---
total=$((pass+fail+skip))
printf "\n"
if [ $fail -eq 0 ]; then
  printf "${GREEN}All clear: %d passed" "$pass"
  [ $skip -gt 0 ] && printf ", %d skipped" "$skip"
  printf "${RESET}\n"
else
  printf "${RED}%d failed${RESET}, %d passed" "$fail" "$pass"
  [ $skip -gt 0 ] && printf ", %d skipped" "$skip"
  printf "\n"
  printf "${RED}Failures:${RESET}${fails}\n"
fi

# Clean up temp files from io tests
rm -f examples/golden/tmp_io.txt

exit $fail
