---
description: 列出 .harness/changes/ 下所有变更目录及其需求名称、中文描述、状态、阶段（可加 --write 刷新 INDEX.md）
argument-hint: "[--all|--active|--closed|--exempt] [--write]"
---

# /list-changes

调用 `.harness/scripts/list_changes.sh` 聚合查询 `.harness/changes/` 下所有变更目录的需求映射。

执行：

```bash
bash .harness/scripts/list_changes.sh $ARGUMENTS
```

**过滤器**（可选，默认 `--all`）：
- `--all`     全部（活跃 + 闭合 + 异常）
- `--active`  仅活跃
- `--closed`  仅已闭合（PASSED + stage=10，与 hook L82–L106 精确字串比较对齐）
- `--exempt`  仅异常/模板（A_R1_CODE_ONLY / {{占位}} 等）

**刷新索引文档**：附加 `--write` → 同时把完整数据（含「原始请求」字段）写入 `.harness/changes/INDEX.md`（自动生成 · 禁止手改）。

输出后请把 stdout 结果原样转述给我（包含汇总行）；如执行了 `--write` 也提示一下 INDEX.md 已刷新，不需要解释字段含义除非我追问。
