---
name: 文档 Wiki 查询与摄取规范
scope: 文档 Wiki 查询消费 / 摄取编排 / 矛盾裁决 / 背景库消费 / 子 Agent 落点
enforce: manual+mechanical
l1_resident: true
rule_kind: 新增模块专属 Rule（与 .harness/rules/ 四件套并列 · 不覆盖既有地基）
version: 2.1.0
updated: 2026-06-22
承接ADR: ADR-001（CLI+退出码契约）· ADR-002（无 MQ 同步状态转换）· ADR-003（git 仓内纯 markdown）· ADR-005（旁路集成）· ADR-006（子 Agent 混合访问）· ADR-009（查询侧采纳度重构 · §2 WK-Q + CLI · §修订 v2/v3 nudge 三抓手 A-2/A-3/SA2-1）· ADR-010（维护侧摄取触发 hook · §6 WK-S）
---

# 规则 · 文档 Wiki 查询与摄取规范（模块专属 · 新增）

> 稳定不变约束。告诉 Agent「文档 Wiki 模块（wiki-engine 集成）的查询消费与摄取编排标准是什么」。
> **本规则为模块级新增 Rule，与 myharness 既有 `.harness/rules/` 四件套（工程结构 / 开发流程规范 / 项目编码规范 + 本规则）并列、不覆盖既有地基**——既有四件套约束 harness 体系 + 业务 demo，本规则约束文档 Wiki 消费。本规则是文档 Wiki 模块的核心消费纪律，承接 M3.2 三条消费契约（查询纪律 / corpus-aware 路由 / 卡收尾增量）+ 错误处理 + 数据生命周期（双刀白名单）。
> **集成深度（旁路）**：承接 ADR-005——wiki 为 Owner / 人 / 子 Agent 按需调用的查询/证据工具，**不进任一阶段门禁判定式、不夺裁决权**；卡收尾增量摄取为 checklist 提示而非阻断（不阻塞主流程交付）。既有 10 阶段 / 元流程门禁裁决不受本规则影响。

## 0. 适用范围

适用于 Owner / 子 Agent 会话对文档 Wiki（`wiki/` 项目文档 corpus + `wiki-background/<c>/` 背景 corpus 接口占位）的**查询消费**与**摄取编排**纪律。不约束 wiki-engine 组件本体实现（组件契约见 ADR 派生 `CLI调用规范.md` + `wiki产物数据规范.md`）。

> **产物根约定**：本规则正文涉及的 `wiki/`（项目文档 corpus）与 `wiki-background/<corpus>/`（背景 corpus）均为**仓库根相对路径**；`wiki/` 目录的实建与首次语料摄取不在本规则范围内（由独立摄取卡执行），本规则只约束其存在后的查询/摄取/裁决/消费纪律。

## 1. 四类纪律总览

| # | 纪律 | 核心约束 | 承接锚点 |
|---|---|---|---|
| WK-Q | 查询纪律 | 调 wiki-query 单命令（命令内承四步 index→rg→两跳→断链回退 + 失败软化）| S-004 / R-003/R-004 / C-003 / ADR-009 |
| WK-I | 摄取纪律 | 双刀白名单 + 每批独立 lint 退出码权威 + 无头自述不可信 | S-002/S-003 / R-006/R-008 / C-005 |
| WK-J | 矛盾裁决纪律 | 禁静默合并 · 留人裁决 · 占位 | S-003 边界 / R-009 / C-001 / O-004 |
| WK-B | 背景库消费纪律 | corpus-aware + 批判性平衡吸收三要点 + 缺位优雅降级 | S-007 / R-015 / C-010 / O-001 |

> 子 Agent 作为 WK-Q / WK-B 消费主体的落点纪律见 §8（WK-SA），承接 ADR-006 混合访问模式。

---

## 2. WK-Q · 查询纪律（调单命令 wiki-query + 命令内部失败软化）

> 承接 ADR-009 + CLI 调用规范 wiki-query 段（CLI-008~012）+ api-design.md §3.1 查询纪律契约。**查询消费形态 = 调 `wiki-query` 单命令**（命令内部承担 index 导航→rg 补候选→两跳溯源→断链回退 + 失败软化 + 在band 提示）；**不再手动执行四步**。

| 编号 | 规则 | 级别 | 校验方式 |
|---|---|---|---|
| WK-Q1 | 知识问答类查询中**需跨多篇文档提炼 / 两跳改写 / 综合归纳**的题（grep 只吐原始噪声、单点 grep 难直接命中）**默认建议先调 `wiki-query "<问题>" [--wiki <corpus>]` 单命令**（命令内部塌缩四步：index 导航 + rg 补候选 + 两跳溯源 + 断链回退，含失败软化 + 在band 提示 · 见 CLI 调用规范 wiki-query 段）；**单文件字面溯源 / 单点出处定位**（"X 在哪 / X 定义在哪行"这类 grep 又快又准的题）**默认走 grep，不必先调 `wiki-query`**（A-2 路由收窄 · ADR-009 §修订 v2 · 仍 nudge 不拦工具 · 效果待 RM-125 采纳率复测证伪）| MUST 人工 | 查询留痕核对 |
| WK-Q2 | 据 `wiki-query` 返回文本作答须**必引其两跳引用**（命中页路径 + 页正文引源路径 · 输出做全的两跳引用是命令契约）| MUST 人工 | 回答证据核对 |
| WK-Q3 | `wiki-query` 未覆盖/断链时**命令内部自动回退 grep**（agent 无须自己判断断链 · 失败软化）；**永不假阴静默——不得以 wiki 漏召当"不存在"、不得臆答**（命令回退兜底 + 纪律明文）| MUST 人工 | 断链回退取证（≥1 故意构造未覆盖查询可回退）|
| WK-Q4 | **"给我答案"用 `wiki-query`**（命令直接两跳溯源）；**"找全部出处"仍可显式 grep 原文**（wiki 是提炼改写、词法召回有损，不依赖 wiki 提炼穷举出处 · 命令在band 提示协同引导）；**`wiki-query` 生态位 = 跨篇综合 / 提炼 / 改写**（grep 无力的题），**字面 / 单点溯源是 grep 主场，不与 grep 抢**——避免在 grep 主场无效推荐 `wiki-query`（无效推荐稀释纪律 salience · A-2 生态位界定）| MUST 人工 | 查询意图分流核对 |

**契约不变量**：查询**永不假阴静默**（QAS-A2 安全网 · 命令回退兜底 + 纪律明文）——词法召回有损不致漏查/臆答。

---

## 3. WK-I · 摄取纪律（双刀白名单 + 退出码权威 + 自述不可信）

> 承接 data-lifecycle.md §2 + event-contracts.md §1 + cross-cutting-error.md §3。摄取走批循环（每批 ≤5 源），**每批独立跑 `wiki-lint`、退出码为权威**，无头摄取会话自述**不作判据**（C-005 铁律）。

### 3.1 账本层双刀白名单（承接 scope §1.1 · 钉死）

> 第一刀 = 体裁分级；第二刀 = 转化判据（信号密度 / 可复用决策价值 vs 模板样板 + 门禁状态流水账）。白名单**承接 scope §1.1 钉死结果，不重判**。

| 维度 | ✅ 值转（高信号 · 卡专属 · 可复用决策/教训/为什么） | ✗ 不转（模板样板 / 门禁状态计数 / 跨卡雷同 · 留 grep） |
|---|---|---|
| **逐体裁白名单** | `spec.md`（真实需求+AC+范围边界）· `summary.md`（做了什么+为什么+例外区）· `failure-record-*`（根因+沉淀+回写 · 金矿）· `proposal-*`（改进决策）· `ADR-*`/`*adr*`（架构决策）· `api-design`/`API设计规范`（接口契约决策）· 元流程 M 阶段产物（`vision`/`requirements`/`scope`/`architecture`/`interface`/`roadmap`）| `ci_result*`（计数）· `deployment_report*`（多 N/A 或 dev 探活）· 各 `*_review_v*`（多为"0 MUST FIX·APPROVED"样板）· `coding_report*` · `unit_test_report*` · `README`（变更目录内）· `module_map*`（实测多 `{{占位}}` 未填）· `project_analysis_report*` |
| **验收层（`.harness/acceptance/`）** | Xc 结论层：`*验收总结报告*`/`*归因报告*`/`*总结报告*`/`*复盘*`/`*验收小结*` · `_behavioral-dimension/` 维度定义高信号篇（`paradigm`/`benefit-scenarios`）· acceptance 内嵌 M 阶段产物（执行时逐篇判 · dogfood-evidence 证据副本不转） | `cases/**` 与 `full-cases/**`（剧本模板化）· `results/**` 与 `full-results/**`（Xb 回填证据流水）· `review/**`（对齐 `*_review_v*` 不转先例）· `runs/**`（执行流水）· `dogfood-sample`/`dogfood-evidence`（证据流水）· `scenario-template`（模板）· `README`（导航样板）· `scripts/**`（非 .md 不扫） |
| **模板文件本身（明确排除 · 一律不转）** | — | **`_TEMPLATE/` · `_PROJ_TEMPLATE/` · `_STAGE_TEMPLATE/`（纯样板目录 · 全部跳过）** |

> 注（验收层人工提升逃生口 · 对齐 WK-J §4 例外体例 · 不破默认白名单）：执行/收尾时发现个别高信号 results/评审篇，可由人工判定单独提升。

| 编号 | 规则 | 级别 | 校验方式 |
|---|---|---|---|
| WK-I1 | 摄取**只摄"值转"体裁**、跳过"不转"体裁与三类模板目录（按上表双刀白名单）；`improvement` 类（failure-record/proposal · R-014 最高信号）一次性建库时**单列最高优先批** | MUST 人工 | 抽样核对（值转入库 / 不转未入库）|
| WK-I2 | **每批结束必须独立跑 `wiki-lint`，以退出码为权威**（exit 0 全绿才 `--commit-batch` + git commit）；无头摄取会话 stdout 自述**不作质量判据**（C-005 铁律）| MUST 机械+人工 | wiki-lint 退出码 |
| WK-I3 | lint exit 1（lint 违规）→ JSON 报告回喂摄取会话修复，按**「约束→批量→模型档」顺序调参**重跑，直到 exit 0；rejected 批**不落 manifest**（不污染基线）| MUST 人工 | 批状态核对 |
| WK-I4 | 摄取所需 API key（`DEEPSEEK_API_KEY`）**走环境变量、不入库**（不写 URL/stdout/日志/文件/提示词 · 对齐既有 R-005/CODE-005）；无 key → `wiki-ingest-cheap` exit 2 诚实报错（不静默降级）| MUST 机械 | secret 扫描 + git diff 无 key |
| WK-I5 | 删除源走 `--forget` 旁路：先清页面引用（防死引用）→ `wiki-rescan --forget --files <已删源>` → 再 lint；`--forget` 只用于**已删除源**（文件仍存在 → exit 2）| MUST 人工 | lint 检查项1/3 兜底 |

> 注：本节 `wiki-lint` 退出码为**组件本体的 lint 检查项**，是摄取批是否可提交的判据；与既有 10 阶段 / 元流程的**质量门禁判定式无关**，不参与、不替换任一阶段门禁裁决（承接 ADR-005 旁路集成）。

### 3.2 批为事务边界（承接 ADR-002/ADR-003）

事务单元 = 一个摄取批（`--begin-batch` → 摄取 → lint → `--commit-batch`）；**批内 lint 全绿才 commit**（事务提交点）；manifest（`state.json`）SHA256 基线单调推进（只在批 committed 时写回）；回滚 = git revert 任意批 commit。

---

## 4. WK-J · 矛盾裁决纪律（禁静默合并 · 留人裁决 · 占位）

> 承接 event-contracts.md §2 ReviewItem 状态机 + cross-cutting-error.md §3 + domain-aggregates.md §2.6。摄取发现矛盾/重复/缺页时**禁止静默合并/改写既有结论**（C-001），登记 `reviews.md` 留人裁决。

| 编号 | 规则 | 级别 | 校验方式 |
|---|---|---|---|
| WK-J1 | 摄取发现与既有页结论**矛盾/重复/缺页** → **禁止静默合并/改写**，登记 `_meta/reviews.md`（`type/source/affected-pages/status` 齐全 · lint 检查项6）`status: open` 条目 | MUST 人工 | lint 检查项6 + 评审 |
| WK-J2 | 裁决用**强模型会话**（不走便宜模型 `wiki-ingest-cheap`，量小、错代价高 · 摄取/裁决主体分离）；裁决落实 → 改受影响页 + 条目 `status: resolved` + `log.md` 追 `## review:<n> \| <UTC> \| <裁决人>` | MUST 人工 | log.md / reviews.md 核对 |
| WK-J3 | ReviewItem 条目**永久保留**作审计痕迹（禁删）；**`lint` 绿 ≠ 无待裁决矛盾**（lint 对 `status: open` 放行）——消费方不得据 lint 绿断定 wiki 内部无冲突 | MUST 人工 | reviews.md 留存核对 |

> **语义占位 · 操作机制留后续卡（O-004/O-005）**：「由 Owner 会话 vs 专门 strategist/reviewer 委派充当裁决者」「裁决是否进 HITL 暂停点」本轮**不固化**（裁决者归属占位 · O-004）；本轮靠组件既有机制（条目留存作审计 · 禁静默合并语义）。`*_review_v*` 默认不转，但含被人工裁决的实质矛盾 / 非样板高信号 MUST FIX 的评审报告，由卡收尾时**人工判定单独提升**（例外走人工 · 不破坏默认白名单 · 与 O-004/O-005 协同 · scope §1.1 边界澄清）。

---

## 5. WK-B · 背景库消费纪律（corpus-aware + 批判性平衡吸收 + 缺位降级）

> 承接 api-design.md §3.2 corpus-aware 路由契约 + qas.md QAS-A4/A5 + cross-cutting-error.md §4。背景 corpus 本轮**接口占位**（O-001 不实接）；本节为前瞻纪律 + 缺位降级底线。

### 5.1 corpus-aware 路由（先选 corpus 再查）

`--wiki <dir>` 单 corpus 语义（一次只操作一个 corpus · C-010）：

| 查询意图 | 目标 corpus | 路径 |
|---|---|---|
| 本项目"做过什么/踩过坑/定过 ADR/规范是什么" | 项目文档 wiki | `--wiki wiki/`（仓库根相对路径）|
| 设计/评审阶段吸收**外部先验经验**（R-015 · 设计+评审类阶段限定）| 背景 wiki（按主题路由）| `--wiki wiki-background/<corpus>/`（O-001 本轮不实接）|

| 编号 | 规则 | 级别 | 校验方式 |
|---|---|---|---|
| WK-B1 | 查询前**先选 corpus 再查**：项目类问题路由 `wiki/`，设计/评审吸收外部先验路由 `wiki-background/<c>/`（`--wiki` 路径均为**仓库根相对路径** · 承接 M3.2 LOW-1 澄清）| MUST 人工 | corpus 路由核对 |
| WK-B2 | **缺位优雅降级（可用性底线）**：背景 corpus 缺位/后到时，设计/评审阶段**照常推进，不报错、不阻断**（无 `wiki-background/<c>/` 则跳过背景查询）；不臆造背景经验 | MUST 人工 | ≥1 次实测设计/评审阶段无背景库可正常完成（QAS-A4）|

### 5.2 批判性平衡吸收三要点（语义占位 · 操作机制留 O-001）

> 承接 R-015 §2.1.1 + QAS-A5。设计/评审阶段消费背景经验时，须**批判性平衡吸收**（防"基于不适用先验作答"的假阳）。**本轮为语义层可对照检查纪律，操作机制（产物项/评审清单项/SOP）留 O-001/O-004 后续卡**。

| 编号 | 规则（语义层 · 可对照检查）| 级别 | 校验方式 |
|---|---|---|---|
| WK-B3 | 对采纳/参考的背景经验条目，须满足三要点：①**完整吸收**——能复述"问题+当时怎么解+最终方案"；②**判适用性**——给出"本项目语境/约束下是否适用"判断；③**可溯留痕**——处置（采纳/改造/不采纳）各附一句理由 | SHOULD（语义层 · 操作机制留 O-001）| 语义对照检查 |
| WK-B4 | 防两种失败模式：**盲目套用**（不判适用性直接搬）/ **浅尝辄止只取缺点**（只看负面不完整吸收）| SHOULD（语义层）| 语义对照检查 |

> **占位说明**：WK-B3/B4 为**语义层纪律占位**——本轮验收 = 纪律语义已落地（三要点 + 两失败模式可对照检查），非机制硬断言；其操作化（产物项/评审清单项/SOP 形态）承接 **O-001**（背景库实接卡）+ **O-004**（裁决归属卡），本规则不写死操作机制。

---

## 6. 卡收尾增量摄取纪律（承接 S-006 · 落 L1/L 通道 · 触发形态 = hook 自动检测 + 纪律兜底）

> 承接 api-design.md §3.3 卡收尾增量摄取契约 + data-lifecycle.md §3 + ADR-010（摄取触发 hook 决策）。**10 阶段卡阶段10 / 元流程 M 阶段 PASSED 时**触发；触发形态 = **非阻塞维护 hook 自动检测（SessionStart detect-only 首选 / Stop 备选）+ 可选异步摄取 + 纪律兜底**（hook 缺位则退化为人手 WK-S 手动摄取 · 增强非依赖）。**不阻塞主流程交付**（checklist 提示 / hook exit 0 永不阻断 · 非门禁 · O-003 · C-A9）。

摄取动作本体（四步 · 不变）：

```
① wiki-rescan --wiki wiki/            → 出 changed/new/deleted 清单
② 按 §3.1 双刀白名单过滤 → 只取"值转"体裁
③ 批循环（每批 ≤5 源）：begin-batch → ingest-cheap → wiki-lint（退出码权威）→ exit 0 才 commit-batch + git commit
④ deleted 源：先清页面引用 → --forget → 再 lint
```

| 编号 | 规则 | 级别 | 校验方式 |
|---|---|---|---|
| WK-S1 | 卡/阶段收尾新增"值转"文档增量喂进 `wiki/`——触发形态 = **hook 自动检测**（detect-only `wiki-rescan --wiki wiki/` 报 new/changed delta · 非阻塞）首选 + 可选异步摄取；**hook 缺位/被禁用时退化为人手卡收尾 rescan + 批循环（纪律兜底）**；不阻塞主流程交付（hook exit 0 永不阻断 · 非门禁 · O-003）| SHOULD（纪律 · 非门禁 · O-003）| checklist / hook 配置核对 |
| WK-S2 | 参考层（docs + rules/skills/agents）"改时增量更新"**并入同一卡收尾纪律**（hook 检测覆盖同一 `--wiki wiki/` corpus · 参考层文档变同样被 detect-only 检测暴露），**不单设独立周期 rescan** | SHOULD | checklist 核对 |
| WK-S3 | 摄取触发 hook = **非阻塞维护 hook**（SessionStart detect-only 首选 / Stop 备选）：恒做检测（read-only · 零成本零出站 · new/changed delta 计数可观测）+ 可选异步后台摄取（key 就绪 · key 缺失/出域被拦优雅降级回退纯 detect）；**全程非阻塞 exit 0**——不挡合并/交付、不进任一阶段门禁判定式、不拦 agent Read/grep、不改 agent 工具选择；corpus 默认仅 `--wiki wiki/`（背景库不入退出判据 · §5）；`--all` 兜底仅覆盖 changed（new 经 os.walk 免疫）；**维护 hook ≠ C-A1/O-A07 禁的消费侧强制 hook**；**阻塞式 pre-merge 摄取明确排除**（不滑门禁 · C-A9/ADR-005）| MUST 人工 | hook 配置 git diff + 非阻塞性对照 |
| WK-S4 | **hook 是增强非依赖**——hook 缺位/被禁用/未配置时，卡收尾增量摄取**退化为纯纪律 WK-S1/WK-S2 手动摄取**（人手 rescan + 批循环）；**新鲜度自动化是增强、不是依赖**（NFR 可用性①）；**不得把 WK-S 纪律全删** | MUST 人工 | 兜底分支在场核对 |

> **L1/L 通道落点**：WK-Q（查询）/ WK-S（卡收尾增量 · 含 hook 触发形态）/ WK-B1（corpus-aware）/ WK-B3-B4（批判吸收语义）面向 **Owner 主会话**的固化落点 = `CLAUDE.md`/`myCLAUDE.md`（L1 常驻 / L 通道体例硬规则）；hook 配置落 `.claude/settings.json`（SessionStart 段 · 与既有 session_start_autosync/autoflip 同落点）。本规则即该纪律的权威 Rule 文件（与四件套并列）；其向 L1 引导文件的镜像引用按既有 L1 体例承载，承接 ADR-005 旁路集成（不焊进门禁）。面向**子 Agent** 的落点（内嵌 + 委派注入）见 §8。

## 7. 例外与豁免

- 任何偏离本规则须在卡收尾 `summary.md` 例外区登记理由与影响面；本规则为模块专属新增 Rule，与既有 `.harness/rules/` 四件套**并列不冲突**（既有四件套约束 harness + 业务 demo，本规则约束文档 wiki 消费）。
- 本规则一律为**旁路纪律**（承接 ADR-005）：不参与任一阶段质量门禁判定式，不夺既有 10 阶段 / 元流程裁决权；MUST 类条目的"机械"校验载体均为组件本体的 secret 扫描 / lint 退出码 / git diff，与流程门禁解耦。

---

## 8. WK-SA · 子 Agent wiki 消费落点纪律（混合模式 · 承接 ADR-006）

> **背景**：WK-Q / WK-B 的消费主体不止 Owner 主会话，还有被 Owner 委派的 sub-agent（generator/reviewer/strategist）。Claude Code 里 sub-agent 经 Task 启动时拿的是 `.claude/agents/<name>.md` 作为 system prompt，**不继承 `CLAUDE.md`/`myCLAUDE.md`（L1）**——故"落点只放 L1"对子 Agent 无效。
> **混合访问模式（承接 ADR-006）**：① **agent 定义内嵌**（WK-Q/WK-B 进各 `.claude/agents/*.md`，子 Agent 天生知 wiki + 会自查）+ ② **委派注入**（Owner 委派时按既有「子 Agent 委派上下文契约」把预查 wiki 页塞进必读清单/摘录）。两机制叠加覆盖子 Agent 消费方。决策记录见 ADR-006。

### 8.1 三落点关系（覆盖全部消费主体）

| 消费主体 | 固化落点 | 知 wiki 的途径 |
|---|---|---|
| Owner / 主会话 | `CLAUDE.md` / `myCLAUDE.md`（L1 常驻） | 会话启动即加载 L1（§2-§6 WK-Q/I/J/B/S 经本规则与 L1 体例承载） |
| 子 Agent（generator/reviewer/strategist） | **① `.claude/agents/{generator,reviewer,strategist}.md` system prompt 内嵌** + **② Owner 委派注入** | 内嵌使其天生知 wiki + 会自查；委派注入由 Owner 预播种相关页 |

> 三落点**协同**：内嵌保证子 Agent **自主可用**（即便 Owner 漏注入也会自查）；委派注入保证**高相关上下文被预播种**（减子 Agent 重复冷查回合）；L1 覆盖 Owner 主会话。三者非互斥（ADR-006 选项 A 混合）。

### 8.2 落点纪律条目

| 编号 | 规则 | 级别 | 校验方式 |
|---|---|---|---|
| WK-SA1 | WK-Q（查询）/ WK-B（背景库消费）对子 Agent 的固化落点 = **`.claude/agents/{generator,reviewer,strategist}.md` system prompt 内嵌**（不止 L1）；理由 = 子 Agent 不继承 `CLAUDE.md` | MUST 人工 | 三 agent 定义内嵌段存在性核对 |
| WK-SA2 | Owner 委派子 Agent 前，**默认先就委派任务关键问题跑一次 `wiki-query` 预查**，再据结果判断：命中有价值的两跳 / 提炼 → 按「子 Agent 委派上下文契约」四要素把预查页塞进必读清单 / 摘录（替代间接指针 · 不得只给"见 `wiki/`"让子 Agent 自行寻路）；**明显无 wiki 受益**（纯字面 / 单点任务）→ Owner 可主动跳过注入。**默认动作 = 先预查；跳过须 Owner 主动判定无受益**（默认动作 ≠ 强制动作 · 非 hook · 非门禁 · 不拦任何工具 · SA2-1 注入默认化 · ADR-009 §修订 v2）；既有委派契约四要素增列一条 wiki 子条款承载本纪律 | MUST 人工 | 委派 prompt 必读清单核对（是否默认先预查 · 受益任务是否含预查页） |
| WK-SA3 | 内嵌纪律须**按各 agent 角色裁剪**（见 §8.3 内嵌 spec），不一刀切全文照搬——generator 只需项目 wiki 查询纪律；reviewer / strategist 还需背景 wiki 消费纪律（R-015 设计/评审阶段限定）| SHOULD | 各 agent 内嵌段裁剪核对 |
| WK-SA4 | 三机制（内嵌 / 委派注入 / L1）**协同非替代**：内嵌保子 Agent 自主可用，委派注入减冷查回合，L1 覆盖 Owner 主会话；缺位降级底线沿用 WK-B2（背景 corpus 缺位不阻断）| MUST 人工 | 协同关系对照检查 |

### 8.3 内嵌 spec（各 agent 定义里加哪一节）

> 本节给出把 wiki 纪律内嵌进各 `.claude/agents/*.md` 的**裁剪 spec**：每段要点 = 调 `wiki-query` 单命令（命令内部承担四步 + 失败软化）+ WK-B corpus-aware / 批判性平衡吸收 / 缺位降级，按角色裁剪。**corpus-aware（WK-B1）+ R-015 批判吸收（reviewer/strategist 的 WK-B3/B4）+ 永不假阴 全保留**（与 §2 同纪律 · 命令承担不了的判断纪律不删）。

| agent 定义 | 内嵌节标题（建议） | 内嵌要点（按角色裁剪） |
|---|---|---|
| `generator.md` | 「wiki 查询纪律（消费方）」 | **调 `wiki-query "<问题>" --wiki wiki/` 单命令**（命令内部承担 index→rg→两跳溯源→断链回退 + 失败软化）；查询路由 `--wiki wiki/`（项目 corpus · WK-B1 仅项目类）；查询永不假阴静默（漏召不当"不存在"、不臆答 · WK-Q3）。**不含背景库消费**（编码阶段非设计/评审阶段，R-015 不适用）|
| `reviewer.md` | 「wiki 查询 + 背景库批判吸收纪律（评审消费方）」 | **调 `wiki-query` 单命令**（命令内部承担四步 + 失败软化 · 项目 corpus 查"做过什么/踩过坑/定过 ADR"）+ **WK-B corpus-aware 路由**（评审吸收外部先验 → `--wiki wiki-background/<c>/`）+ **WK-B3/B4 批判性平衡吸收三要点**（完整吸收 / 判适用性 / 可溯留痕 · 防盲目套用 / 浅尝辄止）+ **WK-B2 缺位优雅降级**（无背景 corpus 照常评审、不阻断）+ 永不假阴 |
| `strategist.md` | 「wiki 查询 + 背景库批判吸收纪律（设计消费方）」 | 同 reviewer（设计阶段亦属 R-015 设计/评审限定）：**调 `wiki-query` 单命令** + **corpus-aware 路由** + **WK-B3/B4 批判吸收三要点** + **WK-B2 缺位降级** + 永不假阴；元流程 M 阶段设计产物吸收背景先验时按此纪律 |

### 8.4 物理落点声明（承接 ADR-005/ADR-006）

- 改 `.claude/agents/{generator,reviewer,strategist}.md`（按 §8.3 内嵌 spec 加节）+ 给 `CLAUDE.md`「子 Agent 委派上下文契约」加一条 **wiki 子条款**（WK-SA2 委派注入纪律入契约四要素）= 子 Agent 落点的物理化动作，由本模块迁移实施卡承载。
- 本规则**定纪律标准 + 内嵌 spec**（本节 + ADR-006）；对 `.claude/agents/*` 真身与 `CLAUDE.md` 的物理 Edit 由各自实施卡按本节 spec 执行（承接 ADR-005 旁路集成，不焊进门禁）。
- 与 §6「L1/L 通道落点」并列：§6 管 Owner 主会话的 L1 固化，本 §8 管子 Agent 的内嵌 + 委派注入固化——两者共同构成"三落点"（§8.1）的完整物理落地清单。

## 9. RS-001 · M0.5 调研衔接纪律（承接 research-discovery-contract-discipline §5 · ADR-007 受控例外）

> 本节是 M0.5 调研阶段（research-discovery skill）的衔接纪律条目，与既有 WK-Q/WK-S/WK-B/WK-SA 并列（编号 RS-* 正交于 WK-*）。承接 `.harness/changes/proj-module-research-phase-20260617/m3_architecture/m3.3_customization/research-discovery-contract-discipline.md` §5 RS-001 设计稿 + ADR-007（M0.5 出口 6 硬门禁 = ADR-005 受控例外）+ ADR-008（厂商无关引擎绑定 + 三级降级链）。

| 编号 | 规则 | 级别 | 校验方式 |
|---|---|---|---|
| **RS-001** | M0.5 调研三源扇出（A 项目内 wiki / B 外部 web / C 人工投喂）须遵守 **RD-TRACE 可溯源 + RD-ADV 对抗校验 + RD-NFN 永不假阴**：关键论断带引用、经证伪/交叉验证留痕、未命中显式标注非静默（断链回退 grep/rg）。research-discovery 是**旁路取证工具纪律**——**除 M0.5 出口 6 硬门禁（ADR-007 受控例外）外不进任一门禁判定式**；M0.5 出口达标由 reviewer 凭 6 门禁判（exit-gate-predicates）。 | MUST 人工（reviewer 评 M0.5 出口）+ SHOULD（主会话 checklist 对照）| reviewer 出口门禁评审 + 人工核对 |

> **旁路定性（ADR-007 BND-2/3）**：RS-001 约束"如何取证、如何留痕"，**不把 research-discovery 引擎/wiki/web 变门禁**——门禁对象是 dossier/open-questions 产出物质量（M0.5 出口 6 硬门禁），不是工具查询动作。M0.5 之外的所有 wiki/codegraph 消费点 100% 维持 ADR-005 旁路语义。
> **缺位降级（NFR-2 / WK-B2 同源）**：无引擎（厂商层引擎不可用）/ 无 corpus（wiki-background/research-* 未建）时，M0.5 调研**静默跳过不阻断**主流程；L3 纯内部源降级仍产合规 dossier（B 源 `explicit_na` + `na_reason`）。
> **执行/评判分离**：RS-001 是对执行侧（strategist）的行为约束（RD-ADV/RD-NFN/RD-TRACE 见 `.harness/skills/research-discovery/SKILL.md` §4）；M0.5 出口达标裁决归 reviewer（6 门禁见 exit-gate-predicates）。
