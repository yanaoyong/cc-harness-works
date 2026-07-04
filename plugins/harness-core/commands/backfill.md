---
description: 验收回填主持剧本——盘点套件 SKIP/缺失案例，逐案例编排 pre→实跑→取证→post→勾认→判定的八步循环（证据全出自确定性脚本，判定权在用户）
argument-hint: "<套件目录> [CASE-ID ...]"
---

# /backfill

以**验收回填主持人**身份运行本剧本（验收簿记操作 · 不建变更卡 · 旁路工具，不进任何阶段门禁判定式、不焊 hook 强制）。约定细节（案例锚点/chains manifest 格式/.evidence 布局/降级路径/独立·链式映射）的权威定义见 `plugins/harness-core/rules/验收回填与证据捕获规范.md`，本剧本不复制其全文。

**角色分工铁律**：交互决策（批次确认、观察点勾认、PASS/FAIL 判定）在你与用户之间；一切进入 result 文件的证据（pre/post 命令输出、transcript 摘录）只能由确定性脚本产出，你零转写。

## §0 组件 bin 定位（双态探测）

先 `git rev-parse --show-toplevel` 推导仓库根，再按序探测组件 bin 目录：

1. `<仓库根>/plugins/harness-core/components/acceptance-backfill/bin/`（本仓开发形态）
2. `${CLAUDE_PLUGIN_ROOT}/components/acceptance-backfill/bin/`（plugin 安装形态）

两处均无 → **明文提示用户"acceptance-backfill 组件缺位，无法回填"并停止，不静默、不徒手替代脚本**。

脚本退出码表（两脚本共用，遇非 0 按此诊断）：

| 退出码 | 语义 |
|---|---|
| 0 | 成功 |
| 1 | 断言性失败（被执行块内命令非零退出） |
| 2 | 参数错误 |
| 3 | （capture 专用）会话定位失败 |
| 4 | （capture 专用）transcript 格式版本不识别 |
| 5 | 内部错误 |

## §1 开局盘点

1. **解析入参**：`$ARGUMENTS` 第一个词 = 套件目录（`.harness/acceptance/` 下目录名，套件根 = 仓库根相对路径 `.harness/acceptance/<套件>/`）；其后可选若干 CASE-ID。套件目录不存在 → 报错停止。
2. **确定候选案例**：
   - 用户给了 CASE-ID → 只取这些案例；
   - 未给 → 扫描套件 `results/` 下 **status=SKIP 或缺失 result 文件**的案例，全部列为候选。
3. **识别链式成员**：读套件 `chains.md`（如在场；不在场则全部按独立案例处理），把候选中属于同一链的案例按链序分组，并按套件 README 依赖表排批次（上游链/案例在前）。
4. **恢复断点**：读 `results/.evidence/.backfill-progress`（如在场）——已定稿案例从批次中剔除，链会话 UUID 钉点沿用（**进度文件续跑**：会话中断后重进 `/backfill` 即从断点继续）。
5. **呈报批次清单**：把案例清单、执行顺序、链分组、断点恢复情况列成表呈给用户，**经用户确认后才开跑**；用户可增删案例或调序。

## §2 单案例八步循环

对批次内每个案例依次执行（链式案例按 §2.9 变体调整）：

1. **读 case 文件**：`cases/<CASE-ID>-*.md`——提取启动 prompt 原文、预期观察点清单、会话工作目录（【运行前】块 `cd` 目标）。
2. **跑前置**：`bash <bin>/acceptance-run.sh pre <套件根> <CASE-ID>`。exit 0 且 `.evidence/<CASE-ID>/pre-skipped.note` 在场 = 占位案例豁免留痕 → 提示用户按案例正文**人工准备**前置条件，不臆造命令。exit 1 → 把失败日志呈给用户定夺（修环境重试 / 跳过本案例）。
3. **发指令卡**：向用户发一张指令卡，包含——
   - 开一个**新的 Claude Code 会话窗口**；
   - `cd` 到哪个工作目录（步骤 1 解析结果）；
   - 粘贴哪段启动 prompt（**用代码围栏原样给出 case 中的 prompt 原文**，不加先验提示、不改一字）；
   - 跑到哪停：独立案例 = 跑完案例操作步骤；链式案例 = 跑到本段 HITL 停下即回；
   - 完成后回本会话说"好了"。
4. **挂起等待**：等用户确认实跑完毕，期间不代跑、不推进。
5. **取证**：`bash <bin>/acceptance-capture.sh`（独立案例 = 按启动 prompt 原文匹配定位会话；链式案例 = 链首钉 UUID 后按进入锚切片，见 §2.9）生成 result 草稿。**多候选会话时把脚本 stderr 的候选列表原样转给用户挑选**。
6. **跑后置**：`bash <bin>/acceptance-run.sh post <套件根> <CASE-ID>`（链式案例仅链尾跑）。
7. **观察点核对**：逐条列出案例预期观察点 + 草稿内对应证据位置（行号/小节），用 AskUserQuestion 让用户**逐条勾认**。全满足 → 建议 PASS；任一不满足 → 引导用户口述偏差，把用户口述写入偏差说明（偏差描述可由你记录，证据文本仍不许你补写）。
8. **定稿判定**：按用户答复把 PASS/FAIL 写入 result（落款 `判定人=用户`），更新 `.backfill-progress`，向用户报告下一个案例。

**回填三字段契约**：result 草稿骨架由 capture 脚本按套件 `results/README.md` 契约生成（如 fullstack-plugin = case_id / status / evidence 三字段），你只在判定字段与偏差说明处按用户答复填写，不重排骨架。

### §2.9 链式编排承接（chains.md 成员）

- **pre 仅链首跑一次，post 仅链尾跑一次**；链中成员跳过步骤 2/6。
- 链首案例按开场 prompt 定位会话后，UUID 钉进进度文件；链内后续成员**不再重匹配**，按 [进入锚, 出口锚) 切片。
- 链中各段在被测会话**停在 HITL 点**时切片定稿本段成员。
- **跑过头**（用户一次推进跨多段）→ 不慌：在链末（或用户回来时）调 capture 按锚一次性回切各成员区间，逐成员补走步骤 7/8。

## §3 硬约束（四条 · 逐条恪守）

1. **禁止转写**——写入 result 的 transcript 内容**只能来自 capture 脚本产出**；主持会话不得凭上下文记忆补写/润色/规整任何证据文本。宁可留空提示人工摘录，不可代笔一字。
2. **判定权在用户**——PASS/FAIL 必须经用户答复，落款"**判定人=用户**"；哪怕证据全绿也不径自代填判定。
3. **写入白名单**——仅允许写 `results/<CASE-ID>-result.md` 与 `results/.evidence/**`；**不改 `cases/`、不改验收对象、不改总结报告**（批次结束把"总结报告待更新项"列成待办清单，提示人工处理）。
4. **guard warning 不计偏差**——守护脚本的 warning 级输出不计入案例偏差；fixture 清零复核沿用套件全局纪律执行。

## §4 异常路径（四条 · 按此降级，永不静默丢证据）

1. **prompt 匹配不到会话**（capture exit 3）→ 展示脚本 stderr 给出的**候选差异提示**（候选会话首条 prompt 摘要），让用户选择：重跑案例，或用 `--session <jsonl路径>` 手工指定会话后重试取证。
2. **transcript 格式版本不识别**（capture exit 4）→ 降级处理：**原始 jsonl 已归档** `.evidence/<CASE-ID>/` + result 该节**留空并写明"待人工摘录"提示**；不静默丢证据、不臆造内容。
3. **案例 FAIL** → 问用户**继续批次还是停下排查**（对照套件依赖表提示下游阻断面）；FAIL 照实回填、不粉饰。
4. **会话中断** → 凭 `results/.evidence/.backfill-progress` 进度文件续跑：重进 `/backfill <套件>` 即从断点继续，已定稿案例不重跑。

## §5 批次收尾

1. 汇总本批次各案例判定（PASS/FAIL/剩余 SKIP）呈给用户。
2. 列出**总结报告待更新项**待办清单（只列不代写，遵守 §3 白名单）。
3. 提示 fixture 清理（套件 `scripts/cleanup_fixtures.sh` 如在场）。
4. 确认 `.backfill-progress` 已反映终态。
