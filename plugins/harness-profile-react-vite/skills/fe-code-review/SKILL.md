---
name: fe-code-review
trigger: 阶段4 FE 编码评审（React+Vite · 与 expert-reviewer 配合）
inputs: 阶段3 FE 代码与 coding_report_vN.md
outputs: 辅助检查项（并入 code_review 报告或 checklist 附页）
version: 1.0.0
updated: 2026-06-28
spec: docs/stage-01-Harness体系建设/02-体系设计/06-Skills技能体系规范.md
stack: react-vite
---

# Skill · FE 代码检查（fe-code-review）

> React+Vite（TypeScript / vitest）栈阶段4 评审检查清单，是后端栈中立 `plugins/harness-core/skills/code-review/` 的 **FE 侧栈特定对等**；与 `expert-reviewer` 执行评审配合，**不替代** reviewer 的评判与结论。

## 1. 目的

对 FE 编码产出做**栈特定**结构化检查（FE 分层职责 / 组件契约 / 状态管理 / 外部调用超时降级 / a11y 等），为 `expert-reviewer` 提供输入。栈无关语义见 `plugins/harness-core/rules/项目编码规范.md §2 通用层 GEN`，FE 栈特定载体见同文件 §4 栈特定层（FE-1~7）；FE 分层见 `plugins/harness-core/rules/工程结构.md §2.4 ES-FE-1~5`。本 skill 不替代 reviewer 结论。

## 2. 触发条件

进入 **阶段4** 时与 `expert-reviewer` + 栈中立 `plugins/harness-core/skills/code-review/` **一并加载**；由 **Reviewer** 执行，Generator 不参与（执行/评判分离）。本 skill 由 Reviewer 直接加载消费，**不依赖 plugin manifest 注册**（plugin.json `skills[]` 是否已登记 fe-code-review 不影响 Reviewer 加载本清单；登记映射属 RM-2026-139 范围）。

## 3. 输入

- `coding/coding_report_vN.md` 与 FE 代码 diff；
- 约束（what）：`plugins/harness-core/rules/项目编码规范.md §4 FE-1~7`；分层（structure）：`plugins/harness-core/rules/工程结构.md §2.4 ES-FE-1~5`；
- FE 分层对照基准：`../fe-coding-skill/specs/01-components-ui.md` ~ `04-services-external.md`（索引见 `../fe-coding-skill/specs/README.md`）。**断链回退**：若 `specs/` 目录缺失，fallback 见 `plugins/harness-core/rules/工程结构.md §2.3/2.4` + `plugins/harness-core/rules/项目编码规范.md §4`（规则文件为权威源，specs 是规则的分层细化参照）。

## 4. 步骤（SOP）

1. 对照检查清单逐项勾选（见下表）。
2. 发现问题写入评审意见（问题 + 建议 + 优先级 MUST FIX/LOW/INFO），汇总进 `code_review_vN.md`。
3. 不单独宣布 APPROVED；**以 expert-reviewer 结论为准**。

### FE 栈特定检查清单（栈特定语义检查项 · 约束载体指向 `plugins/harness-core/rules/项目编码规范.md §4` / `plugins/harness-core/rules/工程结构.md §2.4` / `../fe-coding-skill/specs/`）

| # | 检查项 | 依据 | 优先级口径 |
|---|---|---|---|
| 1 | FE 分层 import 无逆向（components 不直接 import services 越层调后端；services 不 import containers/components；hooks 不 import containers） | ES-FE-1 / ES-FE-2 | 随规则级别（MUST 机械）· **命中默认 MUST FIX** |
| 2 | components 纯展示——无副作用、无 `useEffect` 拉数据、无直接 `fetch`/API 调用（逻辑在 hooks/containers、外部调用在 services） | ES-FE-3 / GEN-4 / FE-4 | 随规则级别（MUST 机械）· **命中默认 MUST FIX** |
| 3 | 金额字段整数分（`priceCents: number` 整数语义，无浮点存金额）；折扣等金额运算用整数运算，无 `float` 中间量 | GEN-1 / FE-2 / R-001 | 随规则级别（MUST）+ reviewer 判断 |
| 4 | **services 层外部调用有 timeout（超时）+ 失败降级**（`AbortController`+`setTimeout` abort 或 axios `timeout`；超时/网络错误返回文档化默认值，不裸抛吞、不空 `catch {}`） | GEN-2 / FE-3 / ES-FE-5 / R-002 | **强绑定 → 命中默认 MUST FIX**（见下方强绑定条） |
| 5 | 命名约定：组件 `PascalCase.tsx` / hooks `useXxx.ts` / services `xxxService.ts`；类型放 `model/` | FE-4 / ES-FE-4 | 随规则级别（SHOULD）+ reviewer 判断 |
| 6 | TS strict（`tsconfig` strict: true）；无 `any` 滥用（显式类型边界） | FE-1 | 随规则级别（SHOULD）+ reviewer 判断 |
| 7 | 组件契约：props 用显式 TS interface、类型边界清晰；受控 vs 非受控一致（不混用） | FE-1 / `specs/01-components-ui.md` | 随规则级别 + reviewer 判断（以 LOW/INFO 为主） |
| 8 | 状态管理：页面级状态归属 containers/hooks，不下沉 components；状态不可变更新（禁原地 mutate）；无不必要的本地状态重复后端真相 | ES-FE-3 / GEN-4 / `specs/02-containers-orchestration.md`、`specs/03-hooks-logic.md` | 随规则级别 + reviewer 判断（以 LOW/INFO 为主） |
| 9 | a11y：语义化标签 / 关键交互可键盘可达 / 必要 aria 属性 | FE 栈特定项 | **LOW/INFO 为主**（非强绑定，不强行 MUST FIX） |
| 10 | 前后端契约对齐：FE `model/` TS 类型与后端 schema 一致（金额单位 / 字段名等跨栈一致） | FE-7 | 随规则级别（MUST 人工）+ reviewer 判断 |
| 11 | 结构化日志，禁裸 `console` 打生产路径 | GEN-5 / FE-6 | 随规则级别（SHOULD）+ reviewer 判断 |
| 12 | 改动范围未超出 spec/tasks | 需求边界 | 随 reviewer 判断 |
| 13 | **业务 error 状态端到端可达**：业务错误（如询价失败 / 校验失败）经 service → hook → container 端到端透传到 UI，不被框架层（路由守卫 / TS 类型收窄 / 全局拦截器）抢先吞掉或改写为通用态（FE-analog of 后端 D-003 错误码 HTTP 可达性） | `specs/04-services-external.md` / GEN-6 | 随规则级别 + reviewer 判断（静态评审盲区，须显式推演） |
| 14 | **测试在代表线上的配置 + 真实交互/并发下运行**：vitest 用例的 mock/fixture 代表线上默认（如真实 `httpClient` 超时/降级路径有覆盖，非永远 happy-path stub）；交互/异步正确性声称有对应用例支撑（FE-analog of 后端 stage2-002 测试配置代表线上+真实并发） | `../fe-coding-skill/SKILL.md` / GEN-2 | 随规则级别 + reviewer 判断（静态评审盲区，须显式核对） |
| 14b | **无密钥/令牌入库**：FE 侧 `services/` 文件及其他前端代码中无 API token/key 硬编码（`import.meta.env` 注入，不入库） | GEN-3 / R-005 | 随规则级别（MUST 机械）· **命中默认 MUST FIX** |
| 15 | **受益场景（CG-Q / WK-Q 命中）下产物有无工具（cg / wiki）调用证据？无 → 记 LOW（非 MUST FIX）** | 行为遵行维度 · `.harness/acceptance/_behavioral-dimension/` | **LOW（非 MUST FIX）**（见下方行为遵行维度条） |

> **检查清单第 4 条 · 强绑定**：本检查项命中 → 评审报告必须标 MUST FIX。对应规则 `项目编码规范.md` FE-3 / ES-FE-5 / GEN-2 / R-002（违规默认 MUST FIX，豁免须 `[HITL-3 豁免 · YYYY-MM-DD · <理由>]` 经人工暂停确认）。评审 Agent 不得自由心证下调到 INFO / LOW。

> **检查清单第 9 条 · a11y/组件契约等 FE 特有项以 LOW/INFO 档为主**：a11y（第 9 条）与组件契约 / 状态管理（第 7/8 条）等 FE 特有项**非强绑定**——记 LOW/INFO 为主，不强行 MUST FIX（避免过度阻断）；仅第 4 条 R-002（FE-3/ES-FE-5 超时降级）沿用后端强绑定 MUST FIX 档。**除第 4 条强绑定 / 第 9 条 a11y 明确 LOW 外**，其余清单项档位写明「随规则级别 + reviewer 判断」（见表内末列），防体例漂移。

> **检查清单第 15 条 · 显著标 LOW（与第 4 条相反 · 守 ADR-005 旁路）**：本检查项命中（受益场景下无工具调用证据）→ 评审报告记 **LOW（非 MUST FIX）**，**不阻断交付**。与第 4 条 R-002 强绑定 MUST FIX **性质相反**，**切勿误套强绑定**：cg / wiki 是旁路工具，留痕缺失只提示「请人去看是否真受益」，不进 pass/fail 门禁。受益场景判据 + 痕迹形态见 `.harness/acceptance/_behavioral-dimension/benefit-scenarios.md`（R1）；**仅「受益场景下」无证据才记 LOW**（不满足受益场景 = 无痕迹不算违规，防假违规 · R1 §3）。

> **检查清单第 13/14 条 · 说明**：对标后端 `plugins/harness-core/skills/code-review/` 第 8/9 条——来源失败记录 `failure-record-stage2-001 §D-003`（错误码 HTTP 可达性）与 `failure-record-stage2-002`（测试配置偏离线上 + 缺真实并发覆盖）。两项均为静态评审固有盲区——纯读 UI/hook 逻辑判「符合」不足，须显式推演 FE error 状态经 service→hook→container 的端到端可达性、核对测试是否在代表性配置/真实交互下运行。FE 侧给出 FE-analog 表态（第 13/14 条）而非静默漏项；若本卡确无对应面（如纯静态展示卡无外部调用），评审报告显式标 N/A 并说明，不留隐性空白。

> **violations.log 起点处理**：每次评审 Skill 启动时，先读取 `.harness/improvement/static-scan-violations.log`，**按本变更目录 scope 过滤**（grep 当前变更目录所影响的文件路径前缀），过滤后集合视为本变更新增的违规集合。
>
> **BLOCKED 触发**：若过滤后集合非空 → 评审报告**必须**标 `BLOCKED`（在 `APPROVED` / `REVISION_REQUIRED` 二档之外的第三档，evidence 类专用）。BLOCKED 状态下游门禁视为未通过。
>
> **HITL-3 豁免出口**：Owner 在评审报告"豁免与例外"区块手写 `[HITL-3 豁免 · YYYY-MM-DD · <理由>]` 即视为通过；豁免后评审报告头部状态改为 `APPROVED (HITL-3 EXEMPTED)`，下游门禁视为通过。Agent **不可**代填豁免声明。

## 5. 产出物

- 检查项结果并入 `../../changes/<变更目录>/coding/review/code_review_vN.md`（满足 `plugins/harness-core/rules/开发流程规范.md` **DF-012**：只含结论 + 证据表 + MUST FIX 清单，禁复述 spec / 大段贴代码 / 流水账）。

## 6. 完成判据

- 清单已覆盖且关键项无未记录的 MUST FIX；
- `code_review_vN.md` 已落盘且 expert-reviewer 结论为 APPROVED（MUST FIX 数 == 0）。

## 7. 引用

- 主评审：`plugins/harness-core/skills/expert-reviewer/`
- 栈中立骨架：`plugins/harness-core/skills/code-review/`（栈中立通用语义检查项 · 本 skill 为 FE 栈特定对等）
- 模板：`plugins/harness-core/_template/_TEMPLATE/coding/review/code_review_v1.md`
- 规则：`plugins/harness-core/rules/`（约束 `项目编码规范.md §4 FE-1~7` / 分层 `工程结构.md §2.4 ES-FE-1~5`）
- FE 分层 Spec（对照基准）：`../fe-coding-skill/specs/01-components-ui.md` ~ `04-services-external.md`（索引 `../fe-coding-skill/specs/README.md`）
