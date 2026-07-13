#!/usr/bin/env bash
# 从 pytest 终端输出解析 passed/total，供阶段 8 填写 ci_result.md
# 用法: pytest -q 2>&1 | tee /tmp/out.txt; .harness/scripts/parse_pytest_summary.sh /tmp/out.txt
# A 轮: .harness/scripts/parse_pytest_summary.sh <(cd harnessdemo/price-service && pytest -q 2>&1)
set -euo pipefail

input="${1:-}"
if [ -z "$input" ] || [ ! -f "$input" ]; then
  echo "usage: parse_pytest_summary.sh <pytest-output-file>" >&2
  exit 1
fi

line=$(grep -E '[0-9]+ passed' "$input" | tail -1 || true)
if [ -z "$line" ]; then
  echo "status=FAILURE"
  echo "total_tests=0"
  echo "passed=0"
  exit 0
fi

passed=$(echo "$line" | grep -oE '[0-9]+ passed' | grep -oE '[0-9]+' | head -1)
failed=$(echo "$line" | grep -oE '[0-9]+ failed' | grep -oE '[0-9]+' | head -1 || true)
failed=${failed:-0}
skipped=$(echo "$line" | grep -oE '[0-9]+ skipped' | grep -oE '[0-9]+' | head -1 || true)
skipped=${skipped:-0}
total=$((passed + failed + skipped))

if [ "${failed:-0}" -eq 0 ] && [ "$total" -gt 0 ]; then
  echo "status=SUCCESS"
else
  echo "status=FAILURE"
fi
echo "total_tests=$total"
echo "passed=$passed"
