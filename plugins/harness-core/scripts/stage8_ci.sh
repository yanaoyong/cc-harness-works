#!/usr/bin/env bash
# stage8_ci.sh — 阶段 8（CI 验证）执行载体：testCommand → outputParser → eval_gate_contract 三段串联。
#
# 定位（proposal-012 §3④ · ADR-005 语义不变）:
#   本脚本只是「执行载体」，不承载门禁判定。冻结判定式唯一可执行源仍是
#   .harness/scripts/eval_gate_contract.sh —— 本脚本不复制、不改写、不旁路该判定逻辑。
#   红路的「归因」（疑似 flaky / 基线既有红 / 真回归）不进脚本，一律留 Owner 判断。
#
# 用法:
#   bash .harness/scripts/stage8_ci.sh                                   # 结果打到 stdout
#   bash .harness/scripts/stage8_ci.sh --card .harness/changes/<变更目录>  # 写 <card>/ci_result/ci_result.md
#   bash .harness/scripts/stage8_ci.sh --out /path/to/ci_result.md
#
# 可选参数:
#   --card <dir>          变更卡目录；输出落 <dir>/ci_result/ci_result.md
#   --out  <file|->       显式输出路径（`-` = stdout）；优先级高于 --card
#   --config <file>       HARNESS_CONFIG.yaml 路径（默认：仓库根 HARNESS_CONFIG.yaml）
#   --cwd <dir>           在该目录下执行 test_command（默认：仓库根）
#   --test-command <str>  覆写 test_command（默认取自 HARNESS_CONFIG.yaml）
#   --parser <pytest|vitest|jest|<path>>  覆写 outputParser 选择（默认：按技术栈标识映射，见下）
#   --log <file>          保存测试原始输出（默认：$TMPDIR 下的临时文件，执行后保留并回显路径）
#   -h | --help
#
# outputParser 映射表（UQ-3 裁量 · 不新增 HARNESS_CONFIG.yaml 字段，按现有字段值做字符串映射）:
#   解析源优先级： --parser 覆写 > stack_backend_test > stack_frontend_test > test_command 首个词元
#   映射规则（小写子串匹配）：
#     *pytest*          → parse_pytest_summary.sh
#     *vitest* / *jest* → parse_vitest_summary.sh
#     其他 / 空         → 不臆测，报错退出（exit 1 + stderr 提示可用 --parser 显式指定）
#
# 退出码语义:
#   0  执行正常 且 gate=PASS
#   2  执行正常 且 gate=FAIL（这是「规则命中」，不是脚本错误：如实输出 FAIL + exact 失败用例清单）
#   1  脚本自身错误：用法错误 / 配置缺失 / test_command 无法执行（命令不存在·不可执行·被信号杀死）
#      / outputParser 解析失败（三行输出格式不全）/ eval_gate_contract 未给出判定
#      —— 任一错误路径均以 stderr 报错原因退出，绝不伪造 gate=PASS。
#
# known-red baseline（可选 · 默认关 · myharness 本仓专属 · chore-ci-baseline-and-stage9-script-20260714）:
#   HARNESS_CONFIG.yaml 扁平键 known_red_baseline_path 指向入库基线清单（永久段 [permanent] + flaky 段 [flaky]）:
#     - 键缺失 或 值为空 → 基线关：行为与本改动前逐字节一致（ci_result.md 全文 + 退出码 · 消费方零影响 · AC-6）。
#     - 键为非空路径     → 基线启用：在冻结判定器 raw gate 之上叠加纯 shell 集合比对——
#         实际失败集 ⊆ 基线集 → baseline-adjusted 绿（exit 0）；有基线外失败 → 红（exit 2）；
#         基线文件缺失/不可读 → fail-closed（exit 1 · 绝不静默判绿 · AC-5）。
#       raw frozen gate 仍如实计算并呈现于 ci_result.md，但基线启用时不驱动退出码（ADR-005 语义不变 · AC-4/AC-21）。
#       flaky 段内条目基线外撞红 → 定点重跑一次（本地 runner），绿即放行、仍红判红；段外基线外失败一律红（AC-8b）。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")"

EVAL_GATE="$SCRIPT_DIR/eval_gate_contract.sh"
PARSER_PYTEST="$SCRIPT_DIR/parse_pytest_summary.sh"
PARSER_VITEST="$SCRIPT_DIR/parse_vitest_summary.sh"

die() { echo "ERROR: $*" >&2; exit 1; }

usage() {
  sed -n '2,45p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
  exit "${1:-1}"
}

# ---------- 参数解析 ----------
card=""
out=""
config=""
run_cwd=""
test_command=""
parser_opt=""
log_file=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --card)          card="${2:-}"; shift 2 ;;
    --card=*)        card="${1#--card=}"; shift ;;
    --out)           out="${2:-}"; shift 2 ;;
    --out=*)         out="${1#--out=}"; shift ;;
    --config)        config="${2:-}"; shift 2 ;;
    --config=*)      config="${1#--config=}"; shift ;;
    --cwd)           run_cwd="${2:-}"; shift 2 ;;
    --cwd=*)         run_cwd="${1#--cwd=}"; shift ;;
    --test-command)  test_command="${2:-}"; shift 2 ;;
    --test-command=*) test_command="${1#--test-command=}"; shift ;;
    --parser)        parser_opt="${2:-}"; shift 2 ;;
    --parser=*)      parser_opt="${1#--parser=}"; shift ;;
    --log)           log_file="${2:-}"; shift 2 ;;
    --log=*)         log_file="${1#--log=}"; shift ;;
    -h|--help)       usage 0 ;;
    *)               echo "ERROR: 未知参数: $1" >&2; usage 1 ;;
  esac
done

config="${config:-$ROOT/HARNESS_CONFIG.yaml}"
run_cwd="${run_cwd:-$ROOT}"

[ -f "$config" ]      || die "配置文件不存在: $config（可从 plugins 包 HARNESS_CONFIG.yaml.template 复制为仓库根 HARNESS_CONFIG.yaml 并填实值）"
[ -d "$run_cwd" ]     || die "--cwd 目录不存在: $run_cwd"
[ -x "$EVAL_GATE" ] || [ -f "$EVAL_GATE" ] || die "冻结判定器缺失: $EVAL_GATE"

# ---------- 扁平 yaml 取值（纯 bash/grep/sed · 零外部依赖 · 与 init_identity.sh 同口径）----------
get_yaml() {
  local key="$1"
  sed -n "s/^${key}:[[:space:]]*//p" "$config" | head -n1 \
    | sed 's/[[:space:]]*$//' \
    | sed 's/^"\(.*\)"$/\1/' \
    | sed "s/^'\(.*\)'\$/\1/"
}

# ---------- AC-1 第一段: test_command ----------
if [ -z "$test_command" ]; then
  test_command="$(get_yaml test_command)"
fi
[ -n "$test_command" ] || die "HARNESS_CONFIG.yaml 未定义 test_command（也未经 --test-command 指定）: $config"

test_path="$(get_yaml test_path)"

# ---------- known-red baseline: 读取配置 + fail-closed 前置（默认关 · AC-5/AC-6）----------
# 键缺失 或 值为空 → baseline_enabled=false：后续基线层完全短路，行为与改动前逐字节一致（AC-6）。
# 键为非空路径 → baseline_enabled=true：此处即做 fail-closed 前置（文件不可读 → die exit 1 · AC-5），
#   在跑测试前尽早失败，绝不静默判绿。
baseline_path="$(get_yaml known_red_baseline_path)"
baseline_enabled="false"
baseline_file=""
if [ -n "$baseline_path" ]; then
  baseline_enabled="true"
  case "$baseline_path" in
    /*) baseline_file="$baseline_path" ;;
    *)  baseline_file="$ROOT/$baseline_path" ;;
  esac
  [ -r "$baseline_file" ] || die "known_red_baseline_path 已配置（'$baseline_path'）但基线文件不可读: $baseline_file（fail-closed · AC-5：基线启用时文件缺失绝不静默判绿）"
fi

# ---------- T3: 条件追加 test_path（AC-14 / AC-14b / AC-15 / AC-16 · fix-script-dist-and-gate-fixes）----------
# 背景：HARNESS_CONFIG.yaml 同时声明 test_command（可能无路径）与 test_path，此前 test_path
#       只用于 ci_result.md 展示、未喂给执行 → 默认调用在仓库根裸跑，误收集仓外测试触发
#       collection error，门禁误 FAIL。
#
# 追加判据（三条件**全真**才追加，缺一不追加）：
#   ① test_path 非空（AC-15：为空 → 不追加，向后兼容只声明 test_command 的消费方）；
#   ② test_command 尚未包含 test_path 值作为子串（AC-16：幂等，不重复追加）；
#   ③ test_command 首个词元命中 **runner 白名单**（AC-14：pytest / python[3] -m pytest /
#      vitest / npx vitest —— 已知「直接吃路径位置参数」的 runner）。
#
# AC-14b（跨栈防伤 · 为何不无条件追加）：前端栈消费方常写 `test_command: npm test`。
#   `npm test tests/` 不加 `--` 分隔符**不会**把路径透传给底层 vitest —— 无条件追加等于给
#   前端 profile 消费方**引入一个新 bug**。故白名单外形态（npm/yarn/pnpm 等包裹器）**一律
#   不追加**，只打印一行提示；执行命令串与本改动引入前**逐字节一致**（零回归）。白名单本身
#   若漏收某 runner（go test / cargo test 等），表现为「不追加 + 提示」= 退回今日行为，
#   失败方向安全。
# 本判据对 --test-command 覆写场景与配置取值场景**同等适用**，不特殊豁免。
runner_takes_path() {
  # $1 = test_command 原串；首个词元（及必要的第二/第三词元）命中白名单 → 0，否则 → 1。
  local cmd="$1"
  local t1 t2 t3
  set -- $cmd                      # 函数内局部位置参数（bash 3.2 兼容 · 不用数组/关联数组）
  t1="$(basename -- "${1:-}")"     # 容忍 /usr/local/bin/pytest 这类绝对路径形态
  t2="${2:-}"
  t3="${3:-}"
  case "$t1" in
    pytest|py.test|vitest) return 0 ;;
    python|python3)                # python -m pytest / python3 -m pytest
      if [ "$t2" = "-m" ] && [ "$t3" = "pytest" ]; then return 0; fi
      return 1 ;;
    npx)                           # npx vitest
      if [ "$t2" = "vitest" ]; then return 0; fi
      return 1 ;;
    *) return 1 ;;
  esac
}

# known-red baseline · flaky 定点重跑用：记录 test_path 追加前的 runner 原串（AC-8b）。
# 重跑单 node-id 时以该原串（剥除与 test_path 完全相等的词元）为 runner 前缀，避免把整个
# test_path 再跑一遍（如 `pytest -q tests/ <node-id>` 会连 tests/ 全量重跑）。
test_command_orig="$test_command"

if [ -n "$test_path" ]; then
  case "$test_command" in
    *"$test_path"*)
      # ② 已显式含 test_path 子串 → 幂等，不追加
      : ;;
    *)
      if runner_takes_path "$test_command"; then
        test_command="$test_command $test_path"
      else
        echo "[stage8_ci] 提示: test_command 首个词元不在 runner 白名单内（pytest / python -m pytest / vitest / npx vitest），已跳过 test_path ('$test_path') 追加。" >&2
        echo "[stage8_ci]       包裹器形态（npm/yarn/pnpm test）追加路径不会透传给底层 runner（缺 '--' 分隔符），追加反而引入新 bug。" >&2
        echo "[stage8_ci]       建议：把完整测试路径直接写进 HARNESS_CONFIG.yaml 的 test_command（如 'npm test -- $test_path'）。" >&2
      fi
      ;;
  esac
fi

# ---------- AC-1 第二段: 按技术栈标识选 outputParser（UQ-3 字符串映射，不新增配置字段）----------
stack_backend_test="$(get_yaml stack_backend_test)"
stack_frontend_test="$(get_yaml stack_frontend_test)"   # 消费方项目若声明则消费；本仓未定义 → 空
first_token="${test_command%% *}"
first_token="$(basename "$first_token")"

parser_hint=""
parser_hint_src=""
if   [ -n "$parser_opt" ];          then parser_hint="$parser_opt";          parser_hint_src="--parser 覆写"
elif [ -n "$stack_backend_test" ];  then parser_hint="$stack_backend_test";  parser_hint_src="HARNESS_CONFIG.yaml:stack_backend_test"
elif [ -n "$stack_frontend_test" ]; then parser_hint="$stack_frontend_test"; parser_hint_src="HARNESS_CONFIG.yaml:stack_frontend_test"
else                                     parser_hint="$first_token";         parser_hint_src="test_command 首个词元"
fi

hint_lc="$(echo "$parser_hint" | tr '[:upper:]' '[:lower:]')"
parser=""
parser_name=""
case "$hint_lc" in
  */*)                                            # 显式给了一条解析器路径
    parser="$parser_hint"; parser_name="$(basename "$parser_hint")" ;;
  *pytest*)  parser="$PARSER_PYTEST"; parser_name="parse_pytest_summary.sh" ;;
  *vitest*)  parser="$PARSER_VITEST"; parser_name="parse_vitest_summary.sh" ;;
  *jest*)    parser="$PARSER_VITEST"; parser_name="parse_vitest_summary.sh" ;;
  *)
    die "无法从技术栈标识推断 outputParser（取值 '${parser_hint}'，来源 ${parser_hint_src}）。
     已支持映射: *pytest* → parse_pytest_summary.sh ; *vitest*|*jest* → parse_vitest_summary.sh
     请显式指定 --parser <pytest|vitest|解析器路径>。脚本不臆测解析器，故此处报错退出。" ;;
esac
[ -f "$parser" ] || die "outputParser 不存在: $parser"

# 失败用例清单的抽取风格随解析器走（pytest 风格 / vitest 风格）
case "$parser_name" in
  parse_pytest_summary.sh) fail_style="pytest" ;;
  parse_vitest_summary.sh) fail_style="vitest" ;;
  *)                       fail_style="generic" ;;
esac

# ---------- 执行 test_command ----------
if [ -z "$log_file" ]; then
  log_file="$(mktemp "${TMPDIR:-/tmp}/stage8_ci_output.XXXXXX")"
fi
: > "$log_file" || die "无法写入测试输出日志: $log_file"

echo "[stage8_ci] test_command : $test_command" >&2
echo "[stage8_ci] cwd          : $run_cwd" >&2
echo "[stage8_ci] outputParser : $parser_name (来源: $parser_hint_src = '$parser_hint')" >&2

set +e
( cd "$run_cwd" && bash -c "$test_command" ) >"$log_file" 2>&1
test_exit=$?
set -e

echo "[stage8_ci] test exit     : $test_exit （原始输出: $log_file）" >&2

# AC-4：区分「脚本自身无法执行测试」与「测试跑了但红」。
#   126 = 命令不可执行 / 127 = 命令不存在 / >=128 = 被信号杀死（进程异常退出）
#   → 均为脚本自身错误：stderr 报错 + 非 0 退出，不生成 ci_result、绝不伪造 PASS。
if [ "$test_exit" -eq 127 ]; then
  echo "----- 原始输出 -----" >&2; cat "$log_file" >&2; echo "--------------------" >&2
  die "test_command 无法执行（exit 127 · 命令不存在 / 依赖缺失）: $test_command"
elif [ "$test_exit" -eq 126 ]; then
  echo "----- 原始输出 -----" >&2; cat "$log_file" >&2; echo "--------------------" >&2
  die "test_command 无法执行（exit 126 · 命令不可执行 / 权限不足）: $test_command"
elif [ "$test_exit" -ge 128 ]; then
  echo "----- 原始输出 -----" >&2; cat "$log_file" >&2; echo "--------------------" >&2
  die "test_command 进程异常退出（exit $test_exit · 疑似被信号终止）: $test_command"
fi

# ---------- AC-1 第二段（续）: outputParser 解析 ----------
set +e
parsed="$(bash "$parser" "$log_file" 2>/dev/null)"
parser_exit=$?
set -e
[ "$parser_exit" -eq 0 ] || die "outputParser 执行失败（exit $parser_exit）: $parser $log_file"

status="$(echo "$parsed"      | grep -oE '^status=[A-Za-z]+'   | head -1 | cut -d= -f2 || true)"
total_tests="$(echo "$parsed" | grep -oE '^total_tests=[0-9]+' | head -1 | cut -d= -f2 || true)"
passed="$(echo "$parsed"      | grep -oE '^passed=[0-9]+'      | head -1 | cut -d= -f2 || true)"

# AC-4：三行输出格式不全 → 非 0 退出 + stderr 报错，不进门禁、不伪造 PASS。
if [ -z "$status" ] || [ -z "$total_tests" ] || [ -z "$passed" ]; then
  echo "----- outputParser 实际输出 -----" >&2; echo "$parsed" >&2; echo "--------------------------------" >&2
  die "outputParser 三行输出格式不全（期望 status= / total_tests= / passed=）: $parser_name"
fi

# ---------- AC-1 第三段: 喂冻结判定器（判定权唯一归 eval_gate_contract.sh）----------
set +e
gate_out="$(echo "$parsed" | bash "$EVAL_GATE" --exit "$test_exit" 2>&1)"
gate_exit=$?
set -e
[ "$gate_exit" -eq 0 ] || die "eval_gate_contract.sh 未给出判定（exit $gate_exit）: $gate_out"

gate="$(echo "$gate_out"        | grep -oE '^gate=[A-Z]+'   | head -1 | cut -d= -f2 || true)"
gate_reason="$(echo "$gate_out" | sed -n 's/^reason=//p'    | head -1 || true)"
case "${gate:-}" in
  PASS|FAIL) : ;;
  *) echo "----- eval_gate_contract 实际输出 -----" >&2; echo "$gate_out" >&2
     die "eval_gate_contract.sh 输出中未取到 gate=PASS|FAIL（判定缺失，拒绝默认放行）" ;;
esac

# ---------- AC-3: exact 失败用例清单（FAIL 路径 · 完整不截断 · 零归因）----------
strip_ansi() { sed -e 's/\x1b\[[0-9;]*[a-zA-Z]//g' "$1"; }

extract_failures() {
  case "$fail_style" in
    pytest)
      # pytest short summary: `FAILED tests/x.py::test_y - AssertionError...` / `ERROR tests/x.py - ...`
      strip_ansi "$log_file" | grep -E '^[[:space:]]*(FAILED|ERROR)[[:space:]]+' | sed 's/^[[:space:]]*//' || true
      ;;
    vitest)
      # vitest: `FAIL  src/x.test.ts > suite > case` / ` × suite > case`
      strip_ansi "$log_file" | grep -E '^[[:space:]]*(FAIL[[:space:]]|(×|✕|✗)[[:space:]])' | sed 's/^[[:space:]]*//' || true
      ;;
    *)
      strip_ansi "$log_file" | grep -E '^[[:space:]]*(FAILED|FAIL|ERROR|×|✕|✗)[[:space:]]+' | sed 's/^[[:space:]]*//' || true
      ;;
  esac
}

failures=""
failure_count=0
if [ "$gate" = "FAIL" ]; then
  failures="$(extract_failures)"
  if [ -n "$failures" ]; then
    failure_count=$(printf '%s\n' "$failures" | grep -c . || true)
  fi
fi

# ---------- known-red baseline: 纯 shell 集合比对层（仅 baseline_enabled=true 时执行 · AC-1/2/8b/9/21）----------
# 定位（ADR-005 语义不变 · AC-4）：本层是叠加的独立判定层——上方 raw gate 由冻结判定器如实给出、
#   零改动、仍在 ci_result.md 呈现；基线启用时最终退出码改随本层 baseline-adjusted verdict（AC-21）。
# 比对键（AC-9）：test node-id——对 `FAILED <file>::<test> - <reason>` / `ERROR <file> - <reason>`
#   剥除 FAILED/ERROR 前缀与 ` - <reason>` 尾串（reason 文案漂移不影响比对）。
# 集合运算（AC-3 纯 shell）：sort -u + comm，零模型/零网络/零密钥。

# 把失败行规整为 node-id 键（stdin → stdout · 每行一个 · 排序去重）
normalize_failure_ids() {
  sed -e 's/^FAILED[[:space:]]*//' -e 's/^ERROR[[:space:]]*//' -e 's/ - .*$//' \
    -e 's/[[:space:]]*$//' | grep -v '^$' | sort -u || true
}

# 从基线文件抽取一节（$1=节名）：节头下一行起至下一节头/EOF；忽略注释行与空行；剥首尾空白。
baseline_section() {
  sed -n "/^\[$1\]/,/^\[/p" "$baseline_file" \
    | grep -v '^\[' | grep -v '^[[:space:]]*#' \
    | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' \
    | grep -v '^$' | sort -u || true
}

baseline_verdict=""        # GREEN | RED（仅 baseline_enabled=true 时有值）
baseline_verdict_label=""
bl_actual_count=0; bl_covered_count=0; bl_red_count=0; bl_flaky_passed_count=0; bl_stale_count=0
bl_covered=""; bl_red=""; bl_flaky_passed=""; bl_flaky_failed=""; bl_stale=""
if [ "$baseline_enabled" = "true" ]; then
  # 格式校验（fail-closed）：基线文件须含 [permanent] 节头，否则视为格式错误（exit 1 · 不静默判绿）。
  grep -q '^\[permanent\]' "$baseline_file" \
    || die "基线文件缺少 [permanent] 节头（格式不可机械解析 · fail-closed）: $baseline_file"

  bl_tmp="$(mktemp -d "${TMPDIR:-/tmp}/stage8_baseline.XXXXXX")"
  printf '%s\n' "$failures" | normalize_failure_ids > "$bl_tmp/actual"
  baseline_section permanent > "$bl_tmp/permanent"
  baseline_section flaky     > "$bl_tmp/flaky"

  bl_actual_count=$(grep -c . "$bl_tmp/actual" || true)
  comm -12 "$bl_tmp/actual" "$bl_tmp/permanent" > "$bl_tmp/covered"   # 基线覆盖（永久段命中）
  comm -23 "$bl_tmp/actual" "$bl_tmp/permanent" > "$bl_tmp/outside"   # 基线外失败集
  comm -13 "$bl_tmp/actual" "$bl_tmp/permanent" > "$bl_tmp/stale"     # stale 告警（永久段未撞红 · R2 增强 · 非阻断）
  comm -12 "$bl_tmp/outside" "$bl_tmp/flaky"    > "$bl_tmp/out_flaky" # 基线外 ∩ flaky 段 → 定点重跑一次
  comm -23 "$bl_tmp/outside" "$bl_tmp/flaky"    > "$bl_tmp/out_hard"  # 基线外 ∖ flaky 段 → 一律红不重跑

  # flaky 定点重跑（AC-8b）：仅 flaky 段内、且落在基线外失败集的条目——对该单 node-id
  # 本地再调用一次测试 runner（恰好一次 · 不循环）；绿→放行并标注，仍红→判红列出。
  # 【injection 硬化 · coding_report_v2】node-id 一律作为**独立 argv 元素**直接传给 runner，
  #   绝不内插进 `bash -c` 字符串——彻底消除 shell 元字符注入面（如基线文件里的恶意 node-id
  #   `tests/x.py::t'; touch /tmp/pwn; echo '` 不再被求值执行），且天然兼容含 `[` `]` `'` 空格的
  #   合法参数化 node-id（无需引号转义）。runner 前缀 = test_path 追加前的 test_command 原串
  #   （剥除与 test_path 完全相等的词元），按词元拆进数组 rerun_cmd[]，直接展开执行（无二次
  #   shell 解析）；node-id 作 runner 的位置参数被当作用例选择器字面收集，非命令行。
  rerun_cmd=()
  if [ -s "$bl_tmp/out_flaky" ]; then
    for bl_tok in $test_command_orig; do
      if [ -n "$test_path" ] && [ "$bl_tok" = "$test_path" ]; then continue; fi
      rerun_cmd+=("$bl_tok")
    done
    while IFS= read -r bl_id; do
      [ -n "$bl_id" ] || continue
      if [ "${#rerun_cmd[@]}" -eq 0 ]; then
        echo "[stage8_ci] flaky 重跑无法构造 runner 前缀（test_command 空）→ 保守判红: $bl_id" >&2
        printf '%s\n' "$bl_id" >> "$bl_tmp/flaky_failed"
        continue
      fi
      echo "[stage8_ci] flaky 定点重跑（恰一次 · AC-8b · node-id 作独立 argv 传参）: ${rerun_cmd[*]} <node-id>" >&2
      set +e
      ( cd "$run_cwd" && "${rerun_cmd[@]}" "$bl_id" ) >>"$log_file.flaky" 2>&1
      bl_rerun_exit=$?
      set -e
      if [ "$bl_rerun_exit" -eq 0 ]; then
        echo "[stage8_ci]   → exit 0（重跑绿 · 放行）" >&2
        printf '%s\n' "$bl_id" >> "$bl_tmp/flaky_passed"
      else
        echo "[stage8_ci]   → exit $bl_rerun_exit（重跑仍红 · 判红）" >&2
        printf '%s\n' "$bl_id" >> "$bl_tmp/flaky_failed"
      fi
    done < "$bl_tmp/out_flaky"
  fi
  : >> "$bl_tmp/flaky_passed"; : >> "$bl_tmp/flaky_failed"

  # 最终基线外红集 = 段外基线外失败 ∪ flaky 重跑仍红
  sort -u "$bl_tmp/out_hard" "$bl_tmp/flaky_failed" | grep -v '^$' > "$bl_tmp/red" || true

  bl_covered="$(cat "$bl_tmp/covered")";           bl_covered_count=$(grep -c . "$bl_tmp/covered" || true)
  bl_red="$(cat "$bl_tmp/red")";                   bl_red_count=$(grep -c . "$bl_tmp/red" || true)
  bl_flaky_passed="$(cat "$bl_tmp/flaky_passed")"; bl_flaky_passed_count=$(grep -c . "$bl_tmp/flaky_passed" || true)
  bl_flaky_failed="$(cat "$bl_tmp/flaky_failed")"
  bl_stale="$(cat "$bl_tmp/stale")";               bl_stale_count=$(grep -c . "$bl_tmp/stale" || true)

  # verdict（AC-21 三态中的 0/2 两态；1=脚本错误已由上方 die 路径承担）：
  #   gate=PASS（真绿·零失败）→ GREEN；
  #   gate=FAIL 且未提取到用例级失败行 → RED（无法归因：收集期错误/total==0 等——基线不掩盖，留 Owner）；
  #   gate=FAIL 且基线外红集为空 → GREEN（raw 红但基线覆盖）；否则 RED。
  if [ "$gate" = "PASS" ]; then
    baseline_verdict="GREEN"; baseline_verdict_label="绿（真绿 · 零失败，未消费基线）"
  elif [ "$bl_actual_count" -eq 0 ]; then
    baseline_verdict="RED";   baseline_verdict_label="红（gate=FAIL 但未提取到用例级失败行——基线无法归因该红，不掩盖：疑似收集期错误 / 用例数 0 / runner 输出格式非预期，留 Owner 处置）"
  elif [ "$bl_red_count" -eq 0 ]; then
    baseline_verdict="GREEN"; baseline_verdict_label="绿（raw 红但全部失败已由基线覆盖）"
  else
    baseline_verdict="RED";   baseline_verdict_label="红（存在基线外失败 · 共 $bl_red_count 条，见下方基线外新增失败清单）"
  fi
fi

# ---------- AC-2: 生成 ci_result.md 机械段（全部字段来自 parser + eval_gate_contract）----------
# 门禁三行表 = 冻结判定式 `exit == 0 && total > 0 && passed == total`（eval_gate_contract.sh:47）
# 三个条件的**如实复述**（ADR-005 · code_review_v1 M-1 修复）：
#   ① 判定权仍唯一归 `eval_gate_contract.sh` —— 下方 `gate`/`verdict` 只取自它的输出，本段不参与裁决；
#   ② 本段只是把该判定器**所依据的三个条件**的取值逐条渲染出来，供 Owner 一眼看出红在哪一条；
#   ③ 因而三个条件必须与冻结判定式**逐字对应**。修前条件① 取 `status == SUCCESS`（parser 由**输出文本**
#      推导，与进程退出码无关），而冻结判定式条件① 是 `exit_code == 0` —— 二者在「摘要行全绿但进程非 0 退出」
#      （收集期错误 / 插件异常 / --cov-fail-under / xdist worker crash）时发散，会生成「三行全『是』、结论
#      『不通过』」的自相矛盾 ci_result.md，把 Owner 推向 AC-3 明令禁止的误归因（"条件都满足却报红 = flaky"）。
#      故条件① 改渲染进程退出码 `$test_exit`；`status` 保留在上方「执行摘要」表（parser 原始产物，不丢失）。
yn() { if [ "$1" = "true" ]; then echo "是"; else echo "否"; fi; }
c1=$([ "$test_exit" -eq 0 ] && echo true || echo false)
c2=$([ "$total_tests" -gt 0 ] && echo true || echo false)
c3=$([ "$passed" -eq "$total_tests" ] && echo true || echo false)
verdict=$([ "$gate" = "PASS" ] && echo "通过" || echo "不通过")

# 一致性兜底（自相矛盾杜绝）：三行表（本地渲染）与 gate（冻结判定器裁决）本应恒等。
# 若因判定式演进/解析异常出现发散 → 显式打一行发散警示（stderr + ci_result.md），绝不静默自相矛盾。
# 注意：发散时**以 gate 为准**（判定权归冻结判定器），本段只负责把发散暴露给 Owner，不自行改判。
divergence=""
if [ "$c1" = "true" ] && [ "$c2" = "true" ] && [ "$c3" = "true" ]; then
  cond_all="PASS"
else
  cond_all="FAIL"
fi
if [ "$cond_all" != "$gate" ]; then
  divergence="⚠ 门禁表三条件（$cond_all）与冻结判定式裁决（gate=$gate · reason=${gate_reason:-n/a}）发散——**以 eval_gate_contract.sh 的裁决为准**；请排查 stage8_ci.sh 的条件渲染是否已偏离 eval_gate_contract.sh 的判定式。"
  echo "[stage8_ci] $divergence" >&2
fi

render() {
  cat <<EOF
# CI 验证结果 · ci_result

> 阶段8 产出。**本文机械段由 \`.harness/scripts/stage8_ci.sh\` 生成**：字段全部取自 outputParser
> (\`$parser_name\`) 与冻结判定器 (\`eval_gate_contract.sh\`) 的实际输出，脚本不臆造数字、不做红路归因。

## 执行摘要（机械段）
| 项 | 值 |
|---|---|
| test_command | \`$test_command\` |
| 执行目录 | \`$run_cwd\` |
| test_path | \`${test_path:-（未声明）}\` |
| outputParser | \`$parser_name\`（来源：$parser_hint_src = \`$parser_hint\`） |
| 进程退出码 | \`$test_exit\` |
| status | \`$status\` |
| total_tests | \`$total_tests\` |
| passed | \`$passed\` |
| 原始输出 | \`$log_file\` |

## 门禁判定（必须全真）
| 条件 | 值 | 是否满足 |
|---|---|---|
| \`exit == 0\` | $test_exit | $(yn "$c1") |
| \`total_tests > 0\` | $total_tests | $(yn "$c2") |
| \`passed == total\` | $passed/$total_tests | $(yn "$c3") |

> 判定源单一（ADR-005）：上表三行是冻结判定式 \`exit == 0 && total > 0 && passed == total\` 三个条件的
> **如实复述**（本脚本不判定）；最终门禁结论唯一取自 \`eval_gate_contract.sh\` → \`gate=$gate\`
> （reason=\`${gate_reason:-n/a}\`）。故三行全「是」 ⟺ \`gate=PASS\`。
> 注：\`status\`（outputParser 由**输出文本**推导，见上方执行摘要表）**不是**门禁条件——测试摘要行可能全绿
> 而进程仍非 0 退出（收集期错误 / 插件异常 / \`--cov-fail-under\` / worker crash），门禁条件① 以进程退出码为准。
${divergence:+
> $divergence
}
## 结论
- 门禁：$verdict
- 不通过回退：用例数 0 → 阶段5；pytest/构建失败 → 阶段3（见 \`开发流程规范.md\` §2.1）
- CI 链接：{{...}}
EOF

  if [ "$gate" = "FAIL" ]; then
    cat <<EOF

## 失败用例清单（exact · 完整不截断）
EOF
    if [ -n "$failures" ]; then
      echo "共 $failure_count 条（原样取自测试输出，未做摘要/截断）："
      echo
      echo '```'
      printf '%s\n' "$failures"
      echo '```'
    else
      cat <<EOF
未能从测试输出中提取到用例级失败行（可能为：用例数 0 / 收集期错误 / 该 runner 输出格式非预期）。
原始输出全文见 \`$log_file\`。脚本不推断原因。
EOF
    fi
    cat <<EOF

## 归因
待 Owner 归因（疑似 flaky / 基线既有红 / 真回归）。**脚本不做归因判断**——本节由 Owner 在阶段 8 人工填写。
EOF
  fi

  # ---- known-red baseline 比对段（仅基线启用时输出 · 基线关时本函数输出与改动前逐字节一致 = AC-6）----
  if [ "$baseline_enabled" = "true" ]; then
    cat <<EOF

## known-red baseline 比对（叠加层 · 纯 shell 集合比对）

> 本节为叠加的独立判定层（AC-4 · ADR-005 语义不变）：上方门禁三行表与 \`gate=$gate\` 仍由冻结判定器
> \`eval_gate_contract.sh\` 如实给出、零改动；基线启用时**最终退出码跟随本节 baseline-adjusted verdict**
> （子集→0 / 超集→2 / 脚本错误→1 · AC-21），raw gate 不再驱动退出码。
> 基线文件: \`$baseline_path\`（入库 tracked · 更新须走变更卡 · AC-7）。比对键 = 剥除 reason 尾串的
> test node-id（AC-9）。

| 项 | 值 |
|---|---|
| baseline-adjusted verdict | $baseline_verdict_label |
| 实际失败 node-id 数 | $bl_actual_count |
| 基线覆盖（永久段命中） | $bl_covered_count |
| 基线外失败（最终判红） | $bl_red_count |
| flaky 重跑后放行 | $bl_flaky_passed_count |
| stale 基线告警（永久段未撞红） | $bl_stale_count |
EOF
    if [ "$gate" = "FAIL" ] && [ "$bl_red_count" -eq 0 ] && [ "$bl_actual_count" -gt 0 ]; then
      cat <<EOF

**全部失败已由基线覆盖**（raw 红但基线覆盖 ≠ 真绿——被覆盖红条目如下，供 Owner 一眼核对）：
EOF
    fi
    if [ -n "$bl_covered" ]; then
      cat <<EOF

### 基线覆盖条目（永久段命中 · 已知既有红）
\`\`\`
$bl_covered
\`\`\`
EOF
    fi
    if [ -n "$bl_red" ]; then
      cat <<EOF

### 基线外新增失败（判红 · 与基线内红分列）
\`\`\`
$bl_red
\`\`\`
EOF
    fi
    if [ -n "$bl_flaky_passed" ]; then
      cat <<EOF

### flaky 重跑后放行（AC-8b · 每条恰重跑一次 · 重跑日志: \`$log_file.flaky\`）
\`\`\`
$bl_flaky_passed
\`\`\`
EOF
    fi
    if [ -n "$bl_flaky_failed" ]; then
      cat <<EOF

### flaky 重跑仍红（已计入上方基线外失败）
\`\`\`
$bl_flaky_failed
\`\`\`
EOF
    fi
    if [ -n "$bl_stale" ]; then
      cat <<EOF

### ⚠ stale 基线告警（非阻断 · R2 增强）
以下永久段条目本次**未**出现在实际失败集——基线可能已过期（对应红已修复），请走变更卡复核收缩基线，抑制基线只增不减：
\`\`\`
$bl_stale
\`\`\`
EOF
    fi
  fi
}

if [ -z "$out" ] && [ -n "$card" ]; then
  [ -d "$card" ] || die "--card 目录不存在: $card"
  mkdir -p "$card/ci_result"
  out="$card/ci_result/ci_result.md"
fi
out="${out:--}"

if [ "$out" = "-" ]; then
  render
else
  mkdir -p "$(dirname "$out")"
  render > "$out"
  echo "[stage8_ci] ci_result 已写入: $out" >&2
fi

echo "[stage8_ci] gate=$gate reason=${gate_reason:-n/a} (status=$status total_tests=$total_tests passed=$passed)" >&2

# ---------- 退出码 ----------
# 基线启用（AC-21）：最终退出码跟随 baseline-adjusted verdict——子集（绿）→0 / 超集（红）→2；
#   脚本自身错误（含基线文件缺失 fail-closed）已在上方 die 路径以 exit 1 承担。
#   raw gate 仍在 ci_result.md 如实呈现，但不驱动退出码（ADR-005 · 判定器本体零改动）。
if [ "$baseline_enabled" = "true" ]; then
  echo "[stage8_ci] baseline-adjusted verdict=$baseline_verdict (actual=$bl_actual_count covered=$bl_covered_count outside_red=$bl_red_count flaky_passed=$bl_flaky_passed_count stale=$bl_stale_count baseline=$baseline_path)" >&2
  if [ "$baseline_verdict" = "GREEN" ]; then
    exit 0
  else
    exit 2
  fi
fi

# 基线关（默认 · AC-6 向后兼容路径）：规则命中（gate=FAIL）如实以 exit 2 返回；与脚本自身错误（exit 1）区分。
if [ "$gate" = "PASS" ]; then
  exit 0
else
  exit 2
fi
