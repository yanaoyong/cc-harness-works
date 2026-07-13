#!/usr/bin/env bash
# 从 vitest run 终端输出解析 passed/total，供阶段 8 填写 ci_result.md
# 输出 schema 与 parse_pytest_summary.sh 逐行恒同（status= / total_tests= / passed=），
# 使 pytest / vitest 两 profile 输出可同喂 eval_gate_contract.sh（BL-INV-1 双向校验）。
# 用法: vitest run 2>&1 | tee /tmp/out.txt; .harness/scripts/parse_vitest_summary.sh /tmp/out.txt
set -euo pipefail

input="${1:-}"
if [ -z "$input" ] || [ ! -f "$input" ]; then
  echo "usage: parse_vitest_summary.sh <vitest-output-file>" >&2
  exit 1
fi

# 锚 vitest `Tests` 摘要行（如 `Tests  5 passed (5)` / `Tests  1 failed | 4 passed (5)`）；
# 排除 `Test Files` 行（文件数非用例数）—— "Test Files" 不含子串 "Tests"，
# 故 grep 'Tests[[:space:]]+[0-9]' 天然只命中用例统计行。
line=$(grep -E 'Tests[[:space:]]+[0-9]' "$input" | tail -1 || true)
if [ -z "$line" ]; then
  # 无可解析 Tests 摘要行（空 stdout / 纯报错）→ 显式 FAILURE，不静默置 SUCCESS（API-BL-3 防假绿）
  echo "status=FAILURE"
  echo "total_tests=0"
  echo "passed=0"
  exit 0
fi

# 子串顺序无关提取（真实 vitest 列序可能为 `1 skipped | 4 passed (5)` · INFO-1）
passed=$(echo "$line" | grep -oE '[0-9]+ passed' | grep -oE '[0-9]+' | head -1 || true)
passed=${passed:-0}
failed=$(echo "$line" | grep -oE '[0-9]+ failed' | grep -oE '[0-9]+' | head -1 || true)
failed=${failed:-0}
skipped=$(echo "$line" | grep -oE '[0-9]+ skipped' | grep -oE '[0-9]+' | head -1 || true)
skipped=${skipped:-0}

# total：优先取 Tests 行括号内 (N) 总数（含 skipped · OQ-2 对齐 pytest 语义）；
# 括号缺失则回退 total=passed+failed+skipped。
paren=$(echo "$line" | grep -oE '\([0-9]+\)' | tail -1 | grep -oE '[0-9]+' || true)
if [ -n "$paren" ]; then
  total=$paren
else
  total=$((passed + failed + skipped))
fi

# status = outputParser 对 stdout 的栈侧布尔投影：failed==0 && total>0 → SUCCESS（与 pytest 解析器同口径）。
# 门禁裁决权最终在 eval_gate_contract.sh 的 passed==total（exit-based 冻结判定式）。
if [ "${failed:-0}" -eq 0 ] && [ "$total" -gt 0 ]; then
  echo "status=SUCCESS"
else
  echo "status=FAILURE"
fi
echo "total_tests=$total"
echo "passed=$passed"
