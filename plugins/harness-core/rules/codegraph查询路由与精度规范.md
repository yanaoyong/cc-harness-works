---
name: codegraph 查询路由与精度规范
scope: 代码符号图查询路由 / 精度消歧 / 新鲜度治理 / 子 Agent 消费落点
rule_kind: 新增模块专属 Rule（与 .harness/rules/ 四件套并列 · 不覆盖既有地基 · codegraph 代码维度孪生）
enforce: manual+mechanical
version: 1.0.0
updated: 2026-06-16
承接ADR: ADR-001（CLI+退出码+`--json` 契约）· ADR-002（`.codegraph/` SQLite 不入仓）· ADR-003（sync 触发=阶段10 纯纪律）· ADR-005（旁路集成）
---

# 规则 · codegraph 查询路由与精度规范（模块专属 · 新增）

> **本规则为模块级新增 Rule，不覆盖 myharness 既有 `.harness/rules/` 四件套，且与 doc-wiki `文档wiki查询与摄取规范.md` 并列共存不冲突**。本规则是代码图谱模块（codegraph 集成）的核心消费纪律，承接 M3.2 三条消费契约（api-design.md §6.1 精度消歧 / §6.2 codegraph-aware 路由 / §6.3 卡收尾增量 sync）+ 错误处理（cross-cutting-error.md §3/§4）+ 新鲜度治理（event-contracts.md §2 + cross-cutting-concurrency）。
> **结构母版**：本规则以 doc-wiki `文档wiki查询与摄取规范.md` 为结构母版，写代码维度孪生版（CG-Q 查询路由 / CG-P 精度纪律 / CG-S 新鲜度治理 / CG-SA 子 Agent 消费落点）。doc-wiki 管文档 corpus（WK-* 前缀），本规则管代码符号图（CG-* 前缀），两套纪律**编号正交、语义并列**。
> **集成深度（旁路）**：承接 ADR-005——codegraph 为 Owner / 人 / 子 Agent 按需调用的查询/证据工具，**不进任一阶段门禁判定式、不夺裁决权**；卡收尾增量 sync 为 checklist 提示而非阻断（不阻塞主流程交付）。本规则现役生效，约束 codegraph 代码符号图消费；既有 10 阶段 / 元流程门禁裁决不受本规则影响。
> **承接 ADR**：ADR-001（CLI+退出码+`--json` 契约）· ADR-002（`.codegraph/` SQLite 不入仓）· ADR-003（sync 触发 = 阶段10 纯纪律）· ADR-005（旁路集成）。

## 0. 适用范围

适用于 Owner / 子 Agent（generator/reviewer/strategist）/ reviewer 会话对 codegraph（代码符号图 · `cg query/callers/callees/impact/files/affected/status`）的**查询消费**与**新鲜度治理**纪律。不约束 codegraph 组件本体实现（组件契约见 ADR 派生 `CLI调用规范-codegraph.md`）。

## 1. 四类纪律总览

| # | 纪律 | 核心约束 | 承接锚点 |
|---|---|---|---|
| **CG-Q** | 查询路由 | codegraph-aware 三分路由（代码符号/关系↔cg · 文档↔wiki · 字面量/错误消息/配置键↔grep）+ 断链回退 grep | R-011 / S-006 / C-001 / C-005① |
| **CG-P** | 精度纪律 | 关系类查询前先 `cg query` 消歧 + `filePath` 核对 + 同模块筛选（恒开 · 不依赖 scorecard 阈值）+ 歧义护栏保留 | R-007/R-008 / S-006 / O-003 |
| **CG-S** | 索引生命周期与新鲜度治理 | **首次全量 init（CG-S0 · 组件接入后一次性 `cg init`）** + 卡收尾增量 sync（阶段10）+ `pendingChanges` 告警兜底 + `git checkout` 漏报覆盖（sync = 维护副作用非门禁）| R-009 / S-008 / C-004 / ADR-003 |
| **CG-SA** | 子 Agent 消费落点 | CG-Q/CG-P 对子 Agent 的内嵌 + 委派注入（子 Agent 不继承 CLAUDE.md）| R-011 / S-006 / ADR-005 |

---

## 2. CG-Q · 查询路由纪律（codegraph-aware 三分路由 + 断链回退）

> 承接 api-design.md §6.2 codegraph-aware 路由契约。**按查询意图选工具**——与 doc-wiki corpus-aware 路由（WK-B1）**并列共存**：查代码符号/关系用 cg，查文档用 wiki，查字面量/错误消息/配置键用 grep。三套工具语义正交，不打架。

### 2.1 三分路由表（先判意图再选工具）

| 查询意图 | 目标工具 | 锚点 |
|---|---|---|
| 代码**符号定位 / 调用关系 / 影响面 / 依赖方向**（"谁调用了 X / 改 X 牵连谁 / X 定义在哪"）| **`cg`（首选 `explore`/`node`；query/callers/callees/impact/files/affected 为精确补充）** | S-003~005 / R-003~006 |
| 代码**字面量 / 错误消息 / 注释 / 配置键**（FTS 召回 0 · 词法无语义）| **`grep`/`rg`**（断链回退底座）| C-001 / O-005 |
| **文档 / Markdown** 检索（"做过什么/踩过坑/定过 ADR/规范是什么"）| **`wiki`**（wiki-engine 组件 · codegraph 机制忽略 `.md` · 二者天然不交叉）| C-005① / 与 WK-B1 并列 |
| 查不到 / 索引过期 / cg 漏召 | **干净回退 `grep`** 找全部出处（不假阴静默）| C-001 / S-006 |

> **主次说明**：`cg` 子命令分主力与精确补充——**`explore`（端到端理解/改动前评估一次拿 verbatim 源码+爆炸半径+already-Read）/ `node`（读符号/读文件 · INSTEAD of Read）为主力**；callers/callees/impact/query/files 为精确补充（按需精确寻址关系/影响面）。本主次口径为 L1 路由 checklist / 默认查询路径，**不进任一阶段门禁判定式（ADR-005 旁路）**；本规则文件为口径权威源，`CLAUDE.md`∥`myCLAUDE.md` 为 L1 镜像、三 agents 为内嵌，均同步指向本源不另定口径（守单源）。

| 编号 | 规则 | 级别 | 校验方式 |
|---|---|---|---|
| CG-Q1 | 代码**符号定位/调用关系/影响面/依赖方向**类查询**优先走 `cg`**（首选 `explore`/`node`；query/callers/callees/impact/files/affected 精确补充）；**不**用 cg 查字面量/错误消息/注释/配置键（FTS 召回 0）| MUST 人工 | 路由意图分流核对 |
| CG-Q2 | **"给我关系/影响面"用 `cg`**（结构化 JSON 带 `filePath:line`）；**"找全部字面出处"必回退 `grep`/`rg`**（cg 词法 FTS 无语义、字面量召回 0，不依赖 cg 穷举出处）| MUST 人工 | 查询意图分流核对 |
| CG-Q3 | `cg query` 查不到符号 / FTS 召回 0 / 索引过期疑似漏报 → **干净回退 `grep`/`rg` 找全部出处**；如实说"cg 未召回/索引过期"再回退，**不得以 cg 漏召当"不存在"、不得臆答**。**退出码引导（非阻塞 · CGCLI-006）**：退 **11**（NOT_INITIALIZED）→ 先 `cg init` 建一次索引再重跑；退 **10**（RUNTIME_MISSING）→ 静默降级 `grep`/`rg` 不阻塞主流程；退 **13**（CG_CLI_ERROR）→ 回退 `grep`/`rg` 找全部出处 + 看 stderr 引擎报错（与卡A SKILL「失败软化」节端到端一致 · C-011）| MUST 人工 | 断链回退取证（≥1 故意构造 cg 召回 0 的查询可回退）|
| CG-Q4 | **代码↔cg / 文档↔wiki 分工清晰**：查代码符号/关系走 cg、查文档/Markdown 走 wiki（两组件语义正交 · codegraph 忽略 `.md`、wiki 管文档）；同一会话内两套路由（CG-Q + WK-Q）**并列共存、按 corpus/意图各走各的，不混用** | MUST 人工 | 工具选择对照（代码问题未误走 wiki / 文档问题未误走 cg）|

**契约不变量**：查询**永不假阴静默**（QAS 安全网 · 对齐 cross-cutting-error §3）——cg 词法召回有损不致漏查/臆答；断链（cg 漏召 / 索引过期）→ 回退 grep 原文。

---

## 3. CG-P · 精度纪律（关系查询前先消歧 · 恒开）

> 承接 api-design.md §6.1 精度消歧查询纪律契约 + scope §7 OQ-2 拍板（精度纪律**无条件常开**、不跑 `--scorecard` 测阈值再调）。按符号名寻址 → 重名/重载合并上报假阳性（"线索"非"结论"）；精度由纪律层显式可筛，而非零假阳性。

### 3.1 关系查询固定前置序列（恒开 · 不依赖 scorecard 阈值 · O-003）

```
① 信 callers/callees/impact 前先 cg query <name> → 看返回几个同名定义（bin/cg def_count = grep -cF '"name": "<name>"'）
② >1 定义（或 stderr 见 ⚠ N symbols named "<name>" 歧义护栏）→ 落歧义区 → 按 filePath 核对
③ 只采信同模块/同项目结果（precision-eval Tier B：手工筛掉跨独立模块的假阳性）
④ search = 词法非语义：用符号名/标识符片段查、非整句自然语言；查不到换词法变体（前缀/子串）
   callers/impact 含 imports/references 边 = "依赖方"非纯"调用方"（解读须区分 · ADR-001 §5.3）
```

| 编号 | 规则 | 级别 | 校验方式 |
|---|---|---|---|
| CG-P1 | 关系类查询（callers/callees/impact）**前置必跑 `cg query <name>`** 看是否多定义；>1 定义 → 落歧义区，按 `filePath` 逐条核对是不是目标定义后才采信。该前置纪律**无条件常开**（OQ-2 · 不依赖 scorecard 量化阈值再开）| MUST 人工 | 关系查询留痕核对（前置 query 步骤存在性）|
| CG-P2 | 依赖适配层 **stderr 歧义护栏**（`⚠ N symbols named "<name>" — results UNION all of them (likely false positives)`）：遇护栏须按提示 `cg query <name>` + 保留 `filePath` 匹配目标定义的结果；护栏组件**须保留**（移植"不可破坏的两条设计约束"之一 · `CG_NO_HINT=1` 可关但默认开 · R-008）| MUST 人工 | 护栏存在性 + 重名查询触发护栏核对 |
| CG-P3 | 只采信**同模块/同项目**结果（手工筛掉跨独立模块的假阳性）；查询输出是"线索"非"结论"——**不得把 cg 单次输出当裁决依据**（旁路证据非裁决 · ADR-005）| MUST 人工 | 同模块筛选留痕 |
| CG-P4 | `search` 是**词法非语义**：用符号名/标识符片段查、非整句自然语言；查不到换词法变体（前缀/子串）后再回退 grep（CG-Q3）。`callers/impact` 含 `imports`/`references` 边 = "依赖方"非纯"调用方"，解读须区分 | MUST 人工 | 查询措辞 + 边语义解读核对 |

**契约不变量**：结果是"线索"非"结论"；歧义名（nest 实测落 68% 撞名区 · 本仓 Python 实际撞名率待实测 · C-008 不外推）必先 `cg query` 消歧；假阳性由纪律层检测消解（"**已知且可控**"非"零假阳性" · precision-eval §5）。

---

## 4. CG-S · 索引生命周期与新鲜度治理纪律（首次全量 init + 卡收尾增量 sync）

> 承接 api-design.md §6.3 卡收尾增量 sync 契约 + event-contracts.md §2 + ADR-003（触发 = 阶段10 纯纪律 checklist 为主）。**10 阶段卡阶段10（HITL-5 用户接受/合并）/ 元流程 M 阶段 PASSED 时的 checklist 纪律项**（不阻塞主流程交付 · 对齐 doc-wiki WK-S 代码维度孪生）。
> **两相模型**：本节涵盖索引生命周期两相——**首次全量建索引（CG-S0 · 组件接入后一次性 `cg init`）** + **卡收尾增量 sync（CG-S1~S5 · 阶段10）**，对齐 doc-wiki 两相模型（一次性全量建库 RM-103/104 ↔ `cg init` · WK-S 增量摄取 ↔ CG-S sync 增量）。

### 4.0 CG-S0 · 首次全量建索引触发约定（索引生命周期起点 · 补齐缺口）

> **缺口背景**：CG-S1~S5 只覆盖「增量 sync」、假设索引已存在；「何时第一次建索引（`cg init`）」原无主动约定——init 被动按 exit 11 提示（撞了才建）。实证后果（c-cg dogfood）：组件装好、运行时在，但从没人 `cg init` → 真仓 `.codegraph/` 空 → query 族退 11 → 一律降级回退 grep，增量约定无从兑现。本子节补齐**首次全量建索引主动触发约定**，使 codegraph 索引生命周期与 doc-wiki **两相模型对称**。

| 编号 | 规则 | 级别 | 校验方式 |
|---|---|---|---|
| CG-S0 | **首次全量建索引主动触发锚点 = 组件首次接入仓库后一次性 `cg init`**：codegraph 组件经 `install-skill` 注册完、运行时就绪（`cg doctor` 显 `runtime:` 非 NONE）后**一次性 `cg init` 建全量索引**（对齐 doc-wiki 一次性建库 RM-103/104）；exit-11 被动提示作 **fallback**（非主锚）。init = 索引生命周期起点（一次性全量）→ 此后走 CG-S1~S5 增量 `cg sync`，两者拼成完整生命周期。| SHOULD（纪律 · 非门禁）| 接入后 `cg doctor` 显 `index: initialized` 核对 |
| CG-S0b | **消费方自检兜底（surfacing · 不焊 hook）**：消费方信任 cg 关系/影响面结果前先 `cg doctor` / `cg status`——`index: NOT initialized`（或查询退 exit 11）→ **先 `cg init` 再用**；`runtime: NONE`（exit 10 无运行时）→ 静默跳过、降级回退 `grep`（与降级链 CG-Q3 / S-007 协同 · 永不假阴静默）。本兜底是**纪律 surfacing 非 hook 强制**。| MUST 人工 | 查询前 `cg doctor`/`status` 自检留痕 |
| CG-S0c | **可选强化 hook 登记不焊（本卡边界）**：session-start 探测无索引则提示 `cg init` 的 hook = **本卡只登记为可选强化、不焊实现**（与 CG-S5 Stop hook 可选强化、`CLI调用规范-codegraph.md` CGCLI-009 候选焊接点只登记不焊**同型**）；**留后续焊接卡**，其前置 = 须先复核并行 **sessionstart autosync hook** 最终形态以保两 hook 触发点正交（一个查询前/起手探测 init、一个交付后 sync）、幂等、无运行时静默跳过、失败不阻断（ADR-003 后果节自洽约束）。**本卡不焊任何 hook。**| SHOULD（登记不焊）| 本卡产物无 hook 实现核对 |

**契约不变量**：首次 init = 一次性全量（生命周期起点 · 主动约定），exit-11 被动提示作 fallback；与增量 sync（CG-S1~S5）拼成完整生命周期。本子节仍守 **ADR-005 旁路铁律**——`cg init` / 索引状态**不进任一阶段门禁判定式、不夺裁决**，是维护副作用 + 消费 surfacing，**不阻塞主流程交付**（无运行时静默跳过）。

### 4.1 卡收尾增量 sync 序列（阶段10 · 纯纪律为主 · ADR-003）

```
① 阶段10 用户接受代码 → cg sync（增量 · 只索引已接受代码 · 回退从不触发 sync = 零 churn）
② cg sync = 维护副作用非门禁判定（不破 ADR-005 旁路 · 不裁决 · 不替换阶段8 pytest 门禁）
③ 消费方查询期先 cg status 看 pendingChanges，≠0 → 纪律提示「先 sync 再信任结果」（第二道兜底 · C-004 = 纪律语义 · 非 cg query 自动 stderr · 触发机制 OQ-7 留 M3.2）
④ git checkout 切分支后 pendingChanges 漏报（git 判文件干净）→ 须显式 cg sync 或 cg index --force（C-004 边界）
⑤ 无运行时（cg doctor: runtime NONE）→ sync 静默跳过不阻塞（与降级协同 · S-007）
```

| 编号 | 规则 | 级别 | 校验方式 |
|---|---|---|---|
| CG-S1 | 卡/阶段收尾（阶段10 用户接受 / M 阶段 PASSED）触发增量 `cg sync` 刷索引；**只索引已接受代码、回退从不触发 sync（零 churn）**；**不阻塞主流程交付**（checklist 提示而非门禁阻断 · ADR-003 主推纯纪律）| SHOULD（纪律 · 非门禁）| checklist 核对 |
| CG-S2 | `cg sync` = **维护副作用非门禁判定**——只刷索引不裁决，不进任一阶段门禁判定式、不替换阶段8 pytest / 阶段4 评审裁决（ADR-005 旁路铁律）| MUST 人工 | 门禁判定式无 cg sync 核对 |
| CG-S3 | 消费方信任关系结果前**先运行 `cg status` 看 `pendingChanges`**；`≠0` → **纪律提示**「先 `cg sync` 再信任结果」（第二道兜底 · 非阻断 · C-004 = 纪律语义 · 触发机制 OQ-7 留 M3.2 · 非 `cg query` 自动 stderr） | MUST 人工 | `cg status` 核对 + 处置核对 |
| CG-S4 | `git checkout`/切分支后 `pendingChanges` 可能漏报（git 判文件干净 · C-004 边界）→ 纪律须**显式覆盖**：切分支后显式 `cg sync` 或 `cg index --force` 重建，不依赖 `pendingChanges` 自动检出 | MUST 人工 | 切分支后显式 sync 留痕 |
| CG-S5 | Stop hook（自动调 sync）为**可选强化**（ADR-003 ②）：若纯纪律漏执行率高再加；若启用须满足自洽约束（与 sessionstart autosync 触发点正交 / `cg sync` 幂等 / 无运行时静默跳过 / hook 失败不阻断）。本规则现役只保留「Stop hook 可选强化（SHOULD · 留后续）」声明，**不焊任何 hook 实现**（机制操作化须复核 sessionstart autosync 并行任务最终形态后再焊）| SHOULD | hook 自洽约束核对（焊接后）|

**契约不变量**：sync 不进门禁；卡内推进期（阶段1-9）索引为"上一已接受态"由查询期 `pendingChanges` 告警兜底；新鲜度兑现 = 卡收尾 sync 纪律 + 告警双重兜底（"已知且可控"非机制保证 · C-004）。

---

## 5. CG-SA · 子 Agent 消费落点纪律（混合模式 · 对齐 doc-wiki WK-SA）

> **堵洞背景（同 doc-wiki WK-SA）**：CG-Q / CG-P 的消费主体不止 Owner 主会话，还有被委派的子 Agent（generator/reviewer/strategist）。Claude Code 里子 Agent 经 Task 启动时拿 `.claude/agents/<name>.md` 作 system prompt，**不继承 `CLAUDE.md`/`myCLAUDE.md`（L1）**——故"落点只放 L1"对子 Agent 无效。须**混合访问模式**：① agent 定义内嵌 + ② 委派注入。

| 编号 | 规则 | 级别 | 校验方式 |
|---|---|---|---|
| CG-SA1 | CG-Q（查询路由）/ CG-P（精度纪律）对子 Agent 的固化落点 = **`.claude/agents/{generator,reviewer,strategist}.md` system prompt 内嵌**（不止 L1）；理由 = 子 Agent 不继承 `CLAUDE.md`（对齐 doc-wiki WK-SA1）| MUST 人工 | 三 agent 定义内嵌段存在性核对 |
| CG-SA2 | Owner 委派子 Agent 时，若任务受益于 cg 代码理解（如阶段4 reviewer 影响面取证），按「子 Agent 委派上下文契约」**把 cg 预查结果 / 相关上下文塞进必读清单或摘录**（替代间接指针 · 不得只给"用 cg"让子 Agent 自行寻路）；既有委派契约 wiki 子条款**并列加一条 codegraph 子条款**（CLAUDE.md / myCLAUDE.md 委派契约 codegraph 适配子条款 CG-SA2）| MUST 人工 | 委派 prompt 必读清单核对 |
| CG-SA3 | 内嵌纪律**按 agent 角色裁剪**：generator 需 CG-Q 路由 + CG-P 精度（编码期定位/影响面）；reviewer 需 CG-P 精度 + CG-S 新鲜度（阶段4 影响面取证须先 sync 再信任）；strategist 设计阶段按需。不一刀切全文照搬 | SHOULD | 各 agent 内嵌段裁剪核对 |
| CG-SA4 | 三机制（内嵌 / 委派注入 / L1）**协同非替代**：内嵌保子 Agent 自主可用，委派注入减冷查回合，L1 覆盖 Owner 主会话；缺位降级底线 = 无运行时静默跳过（CG-S5 / S-007）| MUST 人工 | 协同关系对照检查 |

> **explore/node 主力同步**：子 Agent 内嵌 CG-Q 路由时**同步列 `explore`/`node` 主力**（口径指向本规则 §2.1 / CG-Q1 单源 · 与三 agents 内嵌 `.claude/agents/{generator,strategist}.md` CG-Q 段、`reviewer.md` 阶段4 影响面取证语境一致），**不另定口径**（守 INV-1 单源）。

> **与 doc-wiki WK-SA 的并列关系**：WK-SA 管子 Agent 的 wiki 消费内嵌（查文档），CG-SA 管子 Agent 的 codegraph 消费内嵌（查代码）。各 `.claude/agents/*.md` 的内嵌节**并列两节**（wiki 查询纪律 + codegraph 查询纪律），按角色裁剪、互不覆盖。

---

## 6. 与 doc-wiki 查询纪律的并列共存声明（不冲突证明）

| 维度 | doc-wiki `文档wiki查询与摄取规范.md`（WK-*）| 本规则 `codegraph查询路由与精度规范.md`（CG-*）| 关系 |
|---|---|---|---|
| 管辖 corpus | 文档 / Markdown（`wiki/` + `wiki-background/`）| 代码符号图（`.codegraph/` · 白名单代码扩展名 · 忽略 `.md`）| **正交**（codegraph 机制忽略 `.md` · 二者天然不交叉）|
| 查询路由 | corpus-aware（WK-B1：项目 wiki / 背景 wiki）| codegraph-aware（CG-Q：代码↔cg / 文档↔wiki / 字面量↔grep）| **并列**（CG-Q 显式把"文档→wiki"留给 WK-* · 不抢文档检索）|
| 维护触发 | 一次性全量建库（RM-103/104）+ WK-S 卡收尾增量摄取（阶段10 · 纯纪律 · 入仓 markdown）| **CG-S0 首次全量 `cg init`（组件接入后一次性）+** CG-S 卡收尾增量 sync（阶段10 · 纯纪律 · 不入仓 SQLite）| **同构**（均阶段10 纯纪律 · 产物入仓性相反 · ADR-002/ADR-003）· **两相对称**（一次性全量建 + 卡收尾增量）|
| 旁路边界 | 不进门禁、不夺裁决（ADR-005）| 不进门禁、不夺裁决（ADR-005 复用）| **同构**（均旁路维护副作用）|
| 编号前缀 | `WK-Q/I/J/B/S/SA` | `CG-Q/P/S/SA` | **正交**（编号不撞 · 可同会话并存）|

## 7. 例外与豁免

- 任何偏离本规则须在卡收尾 `summary.md` 例外区登记理由与影响面；本规则为模块专属新增 Rule，与既有 `.harness/rules/` 四件套**并列不冲突**（既有四件套约束 harness + 业务 demo，本规则约束 codegraph 代码符号图消费），与 doc-wiki `文档wiki查询与摄取规范.md`**编号正交、语义并列**（代码↔文档）。
