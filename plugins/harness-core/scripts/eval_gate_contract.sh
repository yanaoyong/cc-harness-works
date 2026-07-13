#!/usr/bin/env bash
# 共享 GateContract 判定器 —— 把冻结判定式收敛为唯一可执行源（C-5 · 逐字等价 api-design §1.2）。
# 冻结判定式: gate = "exit == 0 && total > 0 && passed == total"（跨 profile 恒等 · BL-INV-1）。
# 两 profile 解析器输出（parse_pytest_summary.sh / parse_vitest_summary.sh · schema 恒同）同喂本判定器。
# 用法:
#   parse_*_summary.sh out.txt > parsed.txt; eval_gate_contract.sh parsed.txt --exit 0
#   parse_*_summary.sh out.txt | eval_gate_contract.sh --exit 0
# 入参（OQ-1 双模）：位置参数给「解析器三行输出文件路径」则读文件，否则从 stdin 读；
#                    进程退出码经 `--exit N`（或 `--exit=N`）命名旗标传入，缺省 `--exit 0`。
set -euo pipefail

exit_code=0
infile=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --exit) exit_code="${2:-}"; shift 2 ;;
    --exit=*) exit_code="${1#--exit=}"; shift ;;
    *) infile="$1"; shift ;;
  esac
done

usage() {
  echo "usage: eval_gate_contract.sh [<parser-output-file>] [--exit N]  (or pipe parser output via stdin)" >&2
  exit 1
}

# 双模入参（OQ-1）：可读文件则 cat 文件，否则读 stdin。
if [ -n "$infile" ] && [ -r "$infile" ]; then
  parsed=$(cat "$infile")
else
  parsed=$(cat)
fi

# 从解析器三行输出提取门禁消费的两数值键 total_tests / passed。
total=$(echo "$parsed" | grep -oE '^total_tests=[0-9]+' | head -1 | grep -oE '[0-9]+' || true)
passed=$(echo "$parsed" | grep -oE '^passed=[0-9]+' | head -1 | grep -oE '[0-9]+' || true)

# 解析不全 / 无输入 → usage 报错 exit 1（非静默 PASS）。
if [ -z "${total:-}" ] || [ -z "${passed:-}" ] || [ -z "${exit_code:-}" ]; then
  usage
fi

# 冻结判定式（C-5 唯一可执行源 · 逐字等价 api-design §1.2）：
#   exit == 0 && total > 0 && passed == total  → gate=PASS，否则 FAIL。
# 下方整数比较即该语义的 bash 实现。
if [ "$exit_code" -eq 0 ] && [ "$total" -gt 0 ] && [ "$passed" -eq "$total" ]; then
  echo "gate=PASS"
  echo "reason=all-conditions-met"
else
  echo "gate=FAIL"
  if [ "$exit_code" -ne 0 ]; then
    echo "reason=exit!=0"
  elif [ "$total" -le 0 ]; then
    echo "reason=total==0"
  else
    echo "reason=passed!=total"
  fi
fi
