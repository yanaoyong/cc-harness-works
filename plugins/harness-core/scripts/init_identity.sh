#!/usr/bin/env bash
# init_identity.sh — 从 HARNESS_CONFIG.yaml 幂等生成 application-owner.md 模块一身份段（S-003）。
# 用法:
#   bash .harness/scripts/init_identity.sh
# 行为:
#   读仓库根 HARNESS_CONFIG.yaml（扁平 yaml · 纯 bash/grep/sed 解析 · 零外部依赖 · 不调第三方解析器）,
#   只替换 application-owner.md 中 HARNESS:IDENTITY:START/END 标记块之间的内容（块外字节不动）。
# 幂等: 同一配置连跑两次，application-owner.md 字节一致（标记保留、生成区整体重写）。
# 注: 模块四 10 阶段表格内的对比路径/测试命令引用为人工改静的静态配置指针，本脚本不注入该处。
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")"
CONFIG="$ROOT/HARNESS_CONFIG.yaml"

# R-001 迁移后的 application-owner.md 在 plugins/harness-core/agents/ 下（优先）
# 兼容旧布局：.harness/agents/ 为 fallback
OWNER=""
for candidate in "$ROOT/plugins/harness-core/agents/application-owner.md" "$ROOT/.harness/agents/application-owner.md"; do
  if [ -f "$candidate" ]; then
    OWNER="$candidate"
    break
  fi
done

START_MARK='HARNESS:IDENTITY:START'
END_MARK='HARNESS:IDENTITY:END'

[ -f "$CONFIG" ] || { echo "ERROR: 配置文件不存在: $CONFIG" >&2; exit 1; }
[ -f "$OWNER" ]  || { echo "ERROR: 目标文件不存在: $OWNER" >&2; exit 1; }

# ---------- 扁平 yaml 取值: 取首个 `key:` 行的值, 去行尾空白 + 去首尾引号 ----------
get_yaml() {
  local key="$1"
  sed -n "s/^${key}:[[:space:]]*//p" "$CONFIG" | head -n1 \
    | sed 's/[[:space:]]*$//' \
    | sed 's/^"\(.*\)"$/\1/' \
    | sed "s/^'\(.*\)'\$/\1/"
}

project_name="$(get_yaml project_name)"
project_kind="$(get_yaml project_kind)"
compare_path_a="$(get_yaml compare_path_a)"
compare_path_b="$(get_yaml compare_path_b)"
module_layout="$(get_yaml module_layout)"
stack_backend="$(get_yaml stack_backend)"
stack_backend_framework="$(get_yaml stack_backend_framework)"
stack_backend_test="$(get_yaml stack_backend_test)"
stack_backend_http="$(get_yaml stack_backend_http)"
stack_backend_lint="$(get_yaml stack_backend_lint)"
stack_frontend="$(get_yaml stack_frontend)"

# 顶层目录（用于模块结构 bullet）: 取对比路径首段
pa_top="${compare_path_a%%/*}"
pb_top="${compare_path_b%%/*}"

# 前端栈尾巴（本仓为空则不输出）
fe_tail=""
[ -n "$stack_frontend" ] && fe_tail="；前端 **${stack_frontend}**"

# ---------- 生成区文本（与原模块一第 21–23 行语义等价 · 仅身份值来自 yaml）----------
GENERATED="- 应用名称：**${project_name}**（${project_kind}）；对比测试业务代码：**A 轮** \`${compare_path_a}\`、**B 轮** \`${compare_path_b}\`
- 模块结构：\`.harness/\` 制品 + \`docs/\` + \`${pb_top}/\` / \`${pa_top}/\`（${module_layout}，见 \`test/00-方案与决策/01-对比测试设计方案.md\` v2.2）
- 技术栈与关键中间件：**${stack_backend}**、**${stack_backend_framework}**、**${stack_backend_test}**、**${stack_backend_http}**、**${stack_backend_lint}**（hooks 占位）${fe_tail}；选型见 \`docs/stage-01-Harness体系建设/05-技术栈与工具/14-附录-Step0\`"

# ---------- 标记块校验（缺失则报错而非静默）----------
grep -q "$START_MARK" "$OWNER" || { echo "ERROR: 未找到标记 $START_MARK，先在 application-owner.md 模块一加标记块" >&2; exit 1; }
grep -q "$END_MARK" "$OWNER"   || { echo "ERROR: 未找到标记 $END_MARK" >&2; exit 1; }

# ---------- 块替换: 保留 START/END 标记行, 重写其间内容（ENVIRON 传值避免 -v 转义）----------
tmp="$(mktemp)"
GEN="$GENERATED" awk -v sm="$START_MARK" -v em="$END_MARK" '
  index($0, sm) > 0 { print; print ENVIRON["GEN"]; skip=1; next }
  index($0, em) > 0 { skip=0; print; next }
  skip { next }
  { print }
' "$OWNER" > "$tmp"

mv "$tmp" "$OWNER"
echo "✅ 已据 $CONFIG 刷新 $OWNER 模块一身份段（标记块生成区）"
