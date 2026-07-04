---
description: 列出 .harness/changes/ 下全部流程实例（元流程 proj-* + 10 阶段变更）分组状态（可加 --write 刷新 project/DASHBOARD.md）
argument-hint: "[--all|--active|--closed|--exempt] [--format=plain|json|brief] [--write]"
---

# /flow-status

调用 `.harness/scripts/list_flows.sh`（stage-02 升级版 · 同时处理元流程实例与 10 阶段变更实例）聚合查询流程实例状态。

执行（无参数时默认 `--active --format=plain`，与 CLI 裸跑默认 `--all` 不同 · D-02 §5）：

```bash
args="$ARGUMENTS"
[ -z "$args" ] && args="--active"
bash .harness/scripts/list_flows.sh $args
```

**过滤器**（4 档）：
- `--all`     全部流程实例（含模板/异常）
- `--active`  仅 IN_PROGRESS / REOPENED
- `--closed`  仅闭合（state==PASSED 且无 REOPENED/BLOCKED 子项；10 阶段还需 stage==10，元流程需 M5 PASSED）
- `--exempt`  仅异常/模板（`_*` 模板目录 / ABANDONED / {{占位}} / *CODE_ONLY*）

**输出格式**（3 种）：
- `--format=plain`  分组文本表（默认 · meta / ten-stage / exempt（+unknown）四段）
- `--format=brief`  精简聚合行（hook 注入同款 · 控量）
- `--format=json`   机器可读 JSON（脚本/CI 消费）

**刷新人读视图**：附加 `--write` → 同时刷新 `project/DASHBOARD.md`（聚合视图 · 自动生成勿手改；`project/` 不存在时自动创建）。

用法示例：

```
/flow-status                     # 默认 --active --format=plain
/flow-status --all               # 全部
/flow-status --closed            # 仅闭合
/flow-status --format=json       # JSON 输出（用于脚本）
/flow-status --all --write       # 全量查询 + 刷新 DASHBOARD.md
```

输出后请把 stdout 结果原样转述给我（分组段齐全）；stderr 出现 `warning:` 时一并提示（未注册前缀/命名歧义/坏 summary 等只 warning 不阻塞）。传入不存在的参数时 CLI 会 stderr 报错并 exit 2，把报错信息转述即可。如执行了 `--write` 也提示 DASHBOARD.md 已刷新，不需要解释字段含义除非我追问。
