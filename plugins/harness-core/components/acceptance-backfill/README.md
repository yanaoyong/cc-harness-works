# components/acceptance-backfill — 验收回填证据层

验收套件回填的**确定性脚本证据层**：pre/post 命令执行留档 + 被测会话 transcript 证据捕获（含链式分段切片）。与 `/backfill` 主持剧本（`plugins/harness-core/commands/backfill.md`）构成"主持会话交互层 + 确定性脚本证据层"混合形态——交互决策（批次确认、观察点勾认、PASS/FAIL 判定）留在主持会话与用户之间；**一切进入 result 文件的证据只能由本组件脚本产出，主持会话零转写**。

> 约定权威源：`plugins/harness-core/rules/验收回填与证据捕获规范.md`（案例锚点 / chains manifest / `.evidence/` 布局 / 降级路径 / 独立·链式映射五节）。本 README 只述组件定位与结构，不复制规范内容。

## 组件定位

解决验收套件 Xb 段回填的三处全人工痛点：

1. **三段式命令手工跑** → `bin/acceptance-run.sh` 从 case 回填模板提取【运行前】/【运行后】bash 块并执行，stdout/stderr/退出码 tee 留档 `results/.evidence/<CASE-ID>/`；
2. **对话证据手工复制** → `bin/acceptance-capture.sh` 定位被测会话 JSONL（`~/.claude/projects/<cwd 转义>/`），渲染 transcript 摘录写入 result 草稿【运行中】节，链式案例按 [进入锚, 出口锚) 确定性切片；
3. **批量流程记忆负担** → 进度文件 `results/.evidence/.backfill-progress` 支撑中断续跑与链会话 UUID 钉点（由 `/backfill` 剧本编排消费）。

## 结构（组件四件套）

```
components/acceptance-backfill/
├── bin/
│   ├── acceptance-run.sh      # pre/post 执行器：三段式块提取（归一化容差）+ 执行留档 + env 状态传递 + 占位豁免
│   └── acceptance-capture.sh  # transcript 捕获器：会话定位 / 渲染脱敏 / 三源合并 / 链式切片 / 防御性解析降级
├── test/                      # 守护测试（结构性断言、不消费模型输出）
├── README.md                  # 本文件：组件定位 / 结构 / 旁路声明 / 分发路径决策
└── USAGE.md                   # 两 CLI 用法 / 退出码枚举 / 已知坑
```

## 旁路声明（ADR-005 对齐）

本组件是验收簿记的**效率工具、旁路定位**：

- **不进任一阶段门禁判定式**、不焊 hook 强制触发；`/backfill` 会话按验收簿记操作运行，不建变更卡；
- **判定权在用户**：脚本只产证据，result 草稿判定字段留空，PASS/FAIL 必须经用户答复、落款"判定人=用户"；
- 写入白名单仅 `results/<CASE-ID>-result.md` 与 `results/.evidence/**`——**绝不写 `cases/`、不改验收对象、不改总结报告**；
- 组件缺位不阻断任何主流程，只是回填退回人工。

## 组件分发路径决策（显式注明）

`session-start.sh` 的自动复制清单为 skills/agents/rules/hooks/commands/workflows，**components 不在清单内**（实读脚本确认）。本卡决策 = **不给 session-start.sh 新增 components 复制段**（守"不新建分发机制"边界）。因此 `/backfill` 剧本内定位组件 bin 走**双态探测**：

1. `git rev-parse --show-toplevel` 推导仓库根后，先探 `<仓库根>/plugins/harness-core/components/acceptance-backfill/bin/`（本仓开发形态）；
2. 再探 `${CLAUDE_PLUGIN_ROOT}/components/acceptance-backfill/bin/`（用户项目 plugin 安装形态）；
3. 两处均无 → 剧本**明文提示组件缺位并停止，不静默、不徒手替代脚本**。

## 自测

```sh
bash plugins/harness-core/components/acceptance-backfill/test/*.sh   # 全部 exit 0 即绿
```

守护测试为结构性断言（块提取全集可解析 / 切片锚边界确定性 / 退出码分层 / 脱敏 / 路径零硬编码 / chains 锚一致性），不消费模型输出。操作手册见 **[USAGE.md](USAGE.md)**。
