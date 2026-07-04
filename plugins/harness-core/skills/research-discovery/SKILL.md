---
name: research-discovery
description: 厂商无关的抽象调研 SOP——以一份调研问题清单为入参，对三源（项目内/外部/人工策展）扇出检索，经对抗校验与永不假阴留痕，产出带引用的 dossier 与 open-questions（具体检索引擎由厂商层在绑定点注入，本契约零引擎硬引用）。
trigger: 元流程 M0.5 调研阶段 RUN 时（入口 HITL-0.5 人判 RUN 后加载；判 SKIP 不加载）
inputs: ResearchQuestionSet（调研问题清单 · 抽象 · 不绑引擎入参格式）
outputs: <实例>/m0.5_research/dossier.md + open-questions.md（带引用 · 经校验）
version: 1.0.0
updated: 2026-06-17
spec: .harness/changes/proj-module-research-phase-20260617/m3_architecture/（engine-contract-io / data-schema / handoff-interface / research-discovery-contract-discipline / ADR-B）
---

# Skill · research-discovery（抽象调研契约 SOP）

## 0. 目的与边界

把元流程 **M0.5 调研阶段**的抽象引擎契约固化为一份**厂商无关**的执行 SOP：定义 IN（调研问题清单）/ OUT（带引用 dossier + open-questions）/ BIND（引擎绑定点 · 只声明能力不点名）三要素，以及 DISC 三纪律段（对抗校验 / 永不假阴 / 可溯源）。

> **C-1 厂商隔离承重墙（铁律）**：本 SOP 内**零具体引擎硬引用**——任何具体检索引擎名都不出现在本文件。具体引擎绑定写在 CLAUDE.md 厂商层（C-1 边界外 · 反向绑定：厂商层 → 实现 → 本抽象契约），`.harness/` 不引具体引擎名（ADR-B §3.1 反向禁止）。
> **执行/评判分离**：本 SOP 是抽象契约对**执行侧（strategist）**的行为约束；M0.5 出口 6 门禁的达标裁决归 **reviewer**（BND-3），不在本 SOP 内。
> **不下沉**：引擎 fan-out 编排实现 / 三级链精确退化触发条件（厂商层 O-008）/ 6 门禁判定式表达式（reviewer 侧 exit-gate-predicates）均不入本 SOP。

---

## 1. IN 端口 · ResearchQuestionSet（调研问题清单 · engine-contract-io §2）

抽象契约入参 = 一份**调研问题清单**，**不绑任何引擎的入参格式**（C-1）。

| 字段 | 类型 | 必填 | 说明 |
|---|---|---|---|
| `flow_instance` | string | MUST | 所属元流程实例标识 |
| `run_id` | string | MUST | 本次 RUN 标识（与 dossier 同 · 阶段边界 resume 重跑换新值）|
| `questions` | ResearchQuestion[]（≥1）| MUST | 调研问题清单（≥1 条 · 空清单 = 无可调研 = 应在入口判 SKIP）|
| `scope_note` | string | SHOULD | 本次调研范围/背景摘要（供执行器收敛扇出广度）|

### 1.1 ResearchQuestion 条目

| 字段 | 类型 | 必填 | 说明 |
|---|---|---|---|
| `q_id` | string（如 `Q-01`）| MUST | 问题标识（供 dossier Claim 回溯 / open-questions 关联）|
| `question` | string | MUST | 调研问题正文 |
| `risk_hint` | enum `high`/`medium`/`low` | SHOULD | 风险提示（novel/高风险问题指引扇出深度）|

> **入参厂商无关性自检**：`questions` 是**纯文本问题清单**，**不含任何引擎特定参数**（无 effort/model 等字段）——引擎特定参数由厂商层在绑定点（§3）注入，不进抽象入参（守 C-1）。

> **进入端口语义（HITL-0.5 RUN 分支 · 厂商无关）**：RUN 分支进入时，由 Owner 评估调研问题清单的复杂度/广度/可逆性/风险，**推荐**一组调研规模与执行强度（含模型能力档与检索扇出规模的抽象描述 + 粗略成本/规模提示），交用户**确认或覆盖**（接受推荐 / 换档 / 逐项微调）；最终实选配置随实例留痕。本端口**只声明「Owner 推荐 + 用户确认/覆盖」的抽象交互语义**——不点名任何引擎旋钮/数值/后端（具体档位映射、旋钮实现与模型档专名归厂商层 CLAUDE.md + 本卡 ADR-011 · 守 C-1 承重墙）。规模/强度档**不改变 OUT 端口的 6 门禁达标要求**（永不假阴留痕、对抗校验、可溯源一律照常）；「是否进入(SKIP)」二值准入不在本端口可调范围（人判闸不变）。

---

## 2. OUT 端口 · ResearchOutput = { dossier.md, open-questions.md }（data-schema §1/§6）

OUT 固定 2 件，**缺一即契约未履约**（门禁① 产出物齐全）。落点统一 `<实例>/m0.5_research/`：
- `<实例>/m0.5_research/dossier.md`
- `<实例>/m0.5_research/open-questions.md`

### 2.1 dossier.md schema（data-schema §1）

**frontmatter**：

| 字段 | 类型 | 必填 | 说明 |
|---|---|---|---|
| `artifact` | 常量 `dossier` | MUST | 产出物类型标识 |
| `flow_instance` | string | MUST | 所属元流程实例 |
| `stage` | 常量 `M0.5` | MUST | 阶段标识 |
| `run_id` | string | MUST | 本次 RUN 标识（重跑换新值 · 阶段边界 resume 不复用旧值）|
| `engine_tier` | enum `L1`/`L2`/`L3` | MUST | 本次实际生效的三级链档位（供降级审计 · 档位语义见 §3.2）|
| `sources_disposition` | object（A/B/C 各一）| MUST | 三源处置摘要（见正文「## 三源处置」）|
| `created_at` | ISO-8601 string | MUST | 产出时间戳（UTC）|

**正文「## 三源处置」段**——A/B/C 三个子段，每源一条 SourceProbe：

| 字段 | 类型 | 必填 | 说明 |
|---|---|---|---|
| `source_type` | enum `A`/`B`/`C` | MUST | A=项目内（`--wiki wiki/`）· B=外部（经引擎绑定点）· C=人工投喂（`--wiki wiki-background/research-*/`）|
| `coverage` | enum `covered`/`explicit_na` | MUST | 覆盖痕迹 **或** 显式 N/A——二者必居其一；**缺失 = 静默跳过 = 不达标（永不假阴 RD-NFN）**|
| `na_reason` | string | `coverage==explicit_na` 时 MUST | 显式 N/A 理由（如「C 源本次无人工投喂」/「L3 降级·外部源不可用」）——N/A 必带理由，否则视为静默 |
| `probe_note` | string | SHOULD | 覆盖痕迹摘要（查了什么/命中什么）|
| `corpus_write` | enum `none`/`research-*` | C 源 MUST | C 源若值转写入须标落点 = 隔离 `research-*`（写策展 curated corpus = 不达标）|

> C 源合法路径：`source_type==C && coverage==explicit_na`（无投喂不写）= 合法达标。

**正文「## 关键论断」段**——每条 Claim（影响下游 M1 需求/约束/优先级判断者为「关键」）：

| 字段 | 类型 | 必填 | 说明 |
|---|---|---|---|
| `claim_id` | string（如 `CL-01`）| MUST | 论断标识 |
| `statement` | string | MUST | 论断正文 |
| `citations` | Citation[]（≥1）| MUST | 关键论断 ≥1 引用（可溯源 RD-TRACE · 三式见 §2.3）|
| `provenance` | object | MUST | 来源标注（`source`∈{`curated`,`auto-research`} · `origin_tier`∈{A,B,C} SHOULD）|
| `confidence` | enum `high`/`medium`/`low` | SHOULD | 可信度分级（同等证据下 `curated` 不低于 `auto-research`）|
| `adversarial_check` | object | MUST | 对抗校验痕迹（见 §2.4 · RD-ADV）|
| `hit_sources` | enum[]（A/B/C 子集）| SHOULD | 命中来源（多源命中去重为一条 Claim 时记全部命中源 · 不丢源）|
| `conflict_resolution` | object | OPTIONAL | 多源冲突时裁决留痕（`conflicting_sources`/`verdict`/`rule_applied`∈{curated_priority,evidence_weight,both}/`rationale` · 同等证据下 curated 优先）|

### 2.2 open-questions.md schema（data-schema §6）

**frontmatter**：`artifact: open-questions`(MUST) / `flow_instance`(MUST) / `run_id`(MUST · 关联 dossier 同 run_id)。

**正文 OpenQuestion 段（0..n）**：

| 字段 | 类型 | 必填 | 说明 |
|---|---|---|---|
| `oq_id` | string（如 `OQ-01`）| MUST | 未决问题标识 |
| `question` | string | MUST | 未决问题正文 |
| `handoff_target` | enum `M1`/`defer-roadmap`/`out-of-scope` | MUST | 移交去向（每条必带，否则门禁⑥ 不达标）|
| `related_claims` | string[]（claim_id）| SHOULD | 关联的 dossier 论断（可溯）|
| `handoff_note` | string | SHOULD | 移交说明（`out-of-scope` 时须给理由）|

> `handoff_target` 枚举语义：`M1`=移交 M1 需求挖掘开放问题池（主去向）· `defer-roadmap`=移交 M5 roadmap 后续卡候选 · `out-of-scope`=显式判定本能力边界外。
> **可为空集**——无未决问题时文件**仍须存在非空**（含 frontmatter + 「无未决问题」显式声明），不得缺文件。

### 2.3 Citation 三式（data-schema §2.1 · RD-TRACE）

| 来源 | 格式 | 示例 |
|---|---|---|
| **内部（A 源）** | `kind: internal` · `ref:` = wiki 页路径 **或** 源文件路径（两跳溯源末端）| `ref: wiki/<page>.md` 或 `ref: docs/<...>.md#<anchor>` |
| **外部（B 源）** | `kind: external` · `ref:` = URL · `accessed:` = 访问日期（MUST 带）| `ref: https://... · accessed: 2026-06-17` |
| **人工（C 源）** | `kind: curated_feed` · `ref:` = `wiki-background/research-*` 页路径（值转后）**或** 投喂出处描述 | `ref: wiki-background/research-<topic>/<page>.md` |

> 共用字段：`kind`(MUST) · `ref`(MUST) · `accessed`(external SHOULD) · `quote_or_anchor`(SHOULD)。**断链回退留痕**：A 源两跳断链（wiki 页未覆盖）→ 回退 grep 原文，`ref` 记原文路径并加 `fallback: grep`（RD-NFN）。

### 2.4 AdversarialCheck 留痕（data-schema §2.2 · RD-ADV）

每条关键 Claim 内嵌 `adversarial_check`：`method`∈{`falsification`,`cross_validation`,`both`}(MUST) · `trace`(MUST · 校验痕迹) · `explicit_not_found`(bool MUST) · `not_found_note`(`explicit_not_found==true` 时 MUST)。

### 2.5 下游衔接（handoff-interface §1）

- dossier 关键论断作为**带引用的外部先验**单向供给 M1 需求挖掘（M1 吸收时保留 `claim_id` + citation 链；高 `confidence`/`curated` provenance 优先采信）。
- `handoff_target==M1` 的 OpenQuestion 纳入 M1 开放问题池。
- **衔接方向唯一**：M0.5 → M1 单向先验供给，M1 不回写 M0.5；M0.5 与 M3 解耦（M3 不触发 M0.5 增量刷新 · 先验过时走模式 E REOPEN）。

---

## 3. BIND 端口 · EngineBindingPort（engine-contract-io §4 / ADR-B §3 · C-1 承重核心）

抽象契约**只声明能力契约，不点名引擎**（C-1）。绑定方向：CLAUDE.md 厂商层 → 实现 → 本接口；**反向禁止**（`.harness/` 不引具体引擎名）。

```
EngineBindingPort（抽象 · 厂商无关 · 仅声明能力契约）
  capability_required : "fan-out retrieval over A/B/C sources"（扇出检索能力）
  IN  : ResearchQuestionSet（§1）  +  SourceRoute（三源路由 · §3.1）
  OUT : RawFindings[]（每源原始检索结果 · 待汇聚/合并/对抗校验）
  discipline_required : { adversarial_check, never_false_negative }（纪律契约 · 文本见 §4）
  fallback_contract   : 三级链降级方向（§3.2 · 精确触发条件归 CLAUDE.md 厂商层 O-008）
```

> `capability_required` 是接口的厂商无关声明——任何满足「能对 A/B/C 三源扇出检索」的引擎均可绑定（可插拔）；接口**不约束引擎如何实现 fan-out**，**不含任何引擎特定参数**（无 effort/model 字段 · C-1）。引擎特定参数由厂商层在绑定点注入，不进抽象契约。

### 3.1 SourceRoute（三源路由 · engine-contract-io §4.2）

| 源 | 路由参数 | 厂商无关性 |
|---|---|---|
| **A 项目内** | `--wiki wiki/`（WK-Q 两跳溯源）| 复用既有 wiki-engine 查询（厂商无关）|
| **B 外部** | 经引擎绑定点（具体引擎绑定在 CLAUDE.md 厂商层）| 接口只声明「外部检索」能力，具体引擎边界外 |
| **C 人工投喂** | `--wiki wiki-background/research-*/`（值转后 · 隔离 corpus）| 复用既有 wiki-background 路由（厂商无关）|

> A/C 源复用既有 wiki / wiki-background 查询（厂商无关）；**仅 B 源经引擎绑定点接触厂商层**——故 B 源是唯一跨 C-1 边界的路由。

### 3.2 fallback_contract · 三级降级链（方向 · ADR-B §3.2/§3.3）

接口层只声明「**存在三级降级**」方向；精确触发条件 + 各级引擎实现 = CLAUDE.md 厂商层（O-008），不在本 SOP。

| 档位 | 接口语义（方向 · 不点名引擎）| 降级达标接口 |
|---|---|---|
| **L1** | 首选引擎（厂商内置 · 边界外）| B 源 `coverage==covered` |
| **L2** | 退化自建多源扇出（边界外）| B 源 `coverage==covered`（自建扇出） |
| **L3** | 纯内部源降级（仅 A 源 `wiki/` + 已有 `wiki-background/`）| **B 源 `coverage==explicit_na` + `na_reason="L3 降级·外部源不可用"`** = 满足三源覆盖 |

> **降级方向**：L1 首选引擎 → L2 退化扇出 → L3 纯内部源。**降级达标契约（优雅降级）**：L3 时以「外部源显式 N/A 留痕」满足三源覆盖（不因单一引擎缺位阻断 M0.5）。实际生效档位写 dossier frontmatter `engine_tier` 供审计。
> **永不假阴衔接**：L3 降级的 B 源 N/A **必带 `na_reason`**，否则视为静默跳过（不得以「降级了」为由静默掉 M0.5）。
> **M0.5 入口三档分级 + 引擎绑定/链收敛（指针级 · C-1 边界外）**：M0.5 入口门禁的三档分级（RUN 内 FULL/LITE 细分 + SKIP）及引擎绑定、三级链具体收敛（含档2 RUN_LITE 出口契约：默认跳过引擎 → B 源 `coverage=explicit_na`+`engine_tier=L3`，与真 L3 降级按 `na_reason` 区分）详见厂商层 CLAUDE.md M0.5 引擎绑定节 + 本卡 ADR-010；本抽象契约层**不点名任何具体引擎/后端、不复制其决策**（守 C-1 承重墙）。

---

## 4. DISC 三纪律段（research-discovery-contract-discipline §1/§2/§3）

> 三纪律是抽象契约对**执行侧（strategist）**的行为约束；与既有 wiki（WK-Q）/ codegraph（CG-Q）「断链回退 · 永不假阴」纪律**同源**（C-6）。

### 4.1 RD-ADV · 对抗校验

每条**关键论断**（影响下游 M1 判断者）MUST 做对抗校验，留痕进 dossier `adversarial_check`：

1. **证伪（falsification）**：主动找能推翻该论断的反例/反方证据；`trace` 记「找了什么反例、为何未推翻（或已修正）」。空泛的「未发现反例」不算证伪——须给出**实际尝试的反向检索**。
2. **交叉验证（cross_validation）**：用 **≥2 个相互独立的来源**验证一致性；`trace` 记「哪些独立源一致/不一致」。**单源即下结论 = 不达标**。
3. **method 取值**：`falsification`/`cross_validation`/`both`（关键论断 SHOULD 尽量 `both`；至少其一且 `trace` 非空走过场）。

### 4.2 RD-NFN · 永不假阴（与 WK-Q/CG-Q 断链回退同源）

调研**永不假阴静默**——检索未命中**不得**当作「不存在」、不得臆答、不得静默跳过：

1. **未命中显式标注**：任何「应检索却未命中」MUST 显式标注（`adversarial_check.explicit_not_found == true` + `not_found_note` 说明「哪个问题未检索到 + 已尝试的源/回退路径」）。
2. **断链回退**：
   - **A 源（wiki）**两跳断链（页未覆盖 / 词法漏召）→ **干净回退 grep/rg 原文**，citation `ref` 记原文路径 + `fallback: grep`；如实说「wiki 未覆盖」再回退，不以 wiki 漏召当「不存在」。
   - **B 源（外部）**整体不可用 → L3 降级 + `coverage==explicit_na` + `na_reason`；**不静默掉 B 源**。
   - **codegraph**（若调研涉及既有代码）漏召/索引过期 → 回退 grep/rg 找全部出处，不以 cg 漏召当「不存在」。
3. **三源 N/A 必带理由**：任一源 `coverage==explicit_na` MUST 配 `na_reason`——N/A 无理由 = 静默 = 不达标。

### 4.3 RD-TRACE · 可溯源（RD-ADV/RD-NFN 的前提）

每条关键论断 MUST ≥1 Citation（§2.3 三式）；外部引用带 `accessed`；引用须与论断**相关**（reviewer 判）。可溯源是对抗校验与永不假阴可被审计的前提。

### 4.4 纪律 ≠ 门禁裁决（BND-3）

三纪律是抽象契约对执行侧（strategist）的**行为约束**；M0.5 出口门禁的**达标裁决归 reviewer**（执行/评判分离）。调研用到的 wiki / 外部检索 / codegraph 仍是**旁路取证工具**——本纪律约束「如何取证、如何留痕」，不是把工具变门禁。

---

## 5. 引用

- IN/BIND/注册：`.harness/changes/proj-module-research-phase-20260617/m3_architecture/m3.2_interface/engine-contract-io.md`（§2/§4/§5）
- OUT schema：`.../m3.2_interface/data-schema.md`（§1/§2/§6）
- 下游衔接：`.../m3.2_interface/handoff-interface.md`（§1）
- DISC 纪律文本：`.../m3.3_customization/research-discovery-contract-discipline.md`（§1/§2/§3）
- C-1 厂商无关铁律 + 三级链：`.../m3.3_customization/adr/ADR-B-vendor-neutral-engine-binding-and-three-tier-fallback.md`（§3）
- 厂商层引擎绑定（C-1 边界外 · 非本 SOP）：CLAUDE.md 厂商层（RM-2026-111 落地）
