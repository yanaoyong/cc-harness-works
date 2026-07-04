---
name: fe-coding-skill
description: React+Vite 栈（TypeScript/vitest）编码实现操作 how——FE 侧对等 py-coding-skill，承载阶段3 前端逐层编码步骤序列；引用 §4 FE 约束与 4 份 FE 分层 spec 不复制（C-3 单源）。
trigger_phase: 3
trigger: 阶段3 编码实现（React+Vite 栈 · 与核心 coding-skill 配合，承载 FE 操作 how）
inputs: 已 APPROVED 的 spec.md / tasks.md、绑定声明 react-vite-binding.md（受控前向引用 · 见 §3/§7）、项目编码规范.md §4 FE、fe-coding-skill/specs/ 4 份 FE 分层 Spec
outputs: React+Vite 前端代码、coding_report_vN.md
version: 1.0.0
updated: 2026-06-28
spec: docs/stage-01-Harness体系建设/02-体系设计/06-Skills技能体系规范.md
stack: react-vite
---

# Skill · React+Vite 编码实现（fe-coding-skill）

> **栈特定层 · React+Vite how**。本 skill 承载阶段3 **前端（React+Vite/TypeScript/vitest）操作 SOP（步骤/命令序列）**，是后端 `py-coding-skill` 的 **FE 侧对等**；与栈无关骨架 `plugins/harness-core/skills/coding-skill/` **配合**（骨架管「按 `layeredSpecMapping()` 逐层 + 守 GEN 硬约束」的栈无关流程，本 skill 管「React+Vite 栈下具体怎么做」）。
> **引用不复制（C-3 单源）**：每处 how 旁注指向权威——约束（what）在 `项目编码规范.md §4 FE-x`、分层（structure）在 `工程结构.md §2.4 ES-FE-x`、分层 spec 在 `fe-coding-skill/specs/0N-*.md`、命令实值在绑定声明 `react-vite-binding.md`（⚠ 受控前向引用，见 §3/§7）；本 skill **不重定义** FE-* / ES-FE-* 语义。

## 1. 目的

在 React+Vite（TypeScript / vitest）栈下，按 `layeredSpecMapping()` 返回的 4 份 FE 分层 Spec 逐层落地代码，产出符合 `项目编码规范.md §4 FE` 与 `工程结构.md §2.4 ES-FE` 的实现 + `coding_report_vN.md`。

## 2. 触发条件

进入 **阶段3**（阶段2 APPROVED 且 HITL-2 通过）且 `HARNESS_CONFIG.yaml` `stack` 解析为 react-vite 时，与核心 `coding-skill` 一并加载；**按当前所处层加载对应分层 Spec**（见 `specs/README.md`），不全量加载。

## 3. 输入

- 已 APPROVED 的 `spec.md` / `tasks.md`；
- 绑定声明 `react-vite-binding.md`（testCommand / outputParser / layeredSpecMapping / RequiredCommandRef 的 vitest 实值）——**⚠ 已知受控前向引用：该绑定声明尚未落地**（其 owner 候选 RM-129〔S-001 vitest 解析器/GateContract〕或后续 S-002b-FE 绑定卡；`harness-profile-react-vite/profile/` 目录当前为空）。**与 py-coding-skill 不同**：后端 `python-binding.md` 已由 RM-128 同卡建成（可解析）；本 FE 绑定声明因范围边界（绑定层 ∉ 本 skill 卡 S-006a）暂不建、故悬空且受控——这是体系既定状态、非缺陷。**阶段5 链接完整性核验豁免此受控前向引用。**
- 约束（what）：`plugins/harness-core/rules/项目编码规范.md §4 FE-1~7`；分层（structure）：`plugins/harness-core/rules/工程结构.md §2.4 ES-FE-1~5`；
- 4 份 FE 分层 Spec：`specs/01-components-ui.md` ~ `specs/04-services-external.md`（Spec 来源链 = `specs/README.md`，**可解析、不悬空**）；
- 既有前端代码（变更前先读懂，避免模仿错误 Pattern，如浮点存金额 / fetch 无超时降级 / 组件越层调后端）。

## 4. 步骤（SOP）

1. **范围与分层归属**：读 spec/tasks，按 `工程结构.md §2.4` 确认改动落在 `components/`（UI）→ `containers/`（容器）→ `hooks/`（逻辑）→ `services/`（数据/外部）哪一层；依赖**单向向下**（ES-FE-1/ES-FE-2），`model/` 类型层随各层就近引用。

2. **逐层实现**（对接 4 份 FE 分层 Spec · `layeredSpecMapping()` 在原地引用 · **`layeredSpecMapping()` 的 FE 实值 = `specs/README.md`，引用可解析、不悬空**；加载顺序按 README 的 `NN-` 前缀口径）：
   - **UI 层 `components/*.tsx`**（→ `specs/01-components-ui.md` · ES-FE-3 / FE-4 / GEN-4）：纯展示组件（`PascalCase.tsx`），**只渲染 props + 把交互经 callback props 上抛**；**禁副作用 / 禁 `useEffect` 拉数据 / 禁直接 `fetch` 越层调后端**；props 用显式 TS interface，禁 `any` 滥用（FE-1）。
   - **容器层 `containers/*.tsx`**（→ `specs/02-containers-orchestration.md` · ES-FE-1/ES-FE-2 / `FE-4` / GEN-4）：**编排** UI（组合 `components/`）+ **调** `hooks/` 取状态/数据 + 承接页面级状态，把 hook 返回的 data/handler 经 props 透传给纯展示组件；容器**只编排+委托、不堆业务、不直接 `fetch`**（外部数据获取下沉 hooks→services）。
   - **逻辑层 `hooks/useXxx.ts`**（→ `specs/03-hooks-logic.md` · ES-FE-1/ES-FE-3 / GEN-1/GEN-4/GEN-6）：可复用业务逻辑 / 副作用 / 状态封装（`useXxx`）；副作用经 `useEffect`/`useCallback` 显式声明依赖 + 清理函数（取消 `AbortController`/订阅/定时器）；金额整数运算见第 3 步；调后端经 services（hooks 不直接 `fetch`）；状态**不可变更新**（禁原地 mutate），派生值用 `useMemo`；状态形状字段与后端 `model/` schema 对齐（FE-7）。
   - **数据/外部层 `services/xxxService.ts`**（→ `specs/04-services-external.md` · ES-FE-2/ES-FE-5 / FE-3 / GEN-2/GEN-3/GEN-6/GEN-7）：对后端 API 的调用封装（`xxxService`）+ 统一 `httpClient`；外部调用超时 + 降级见第 4 步；返回**领域模型**（非裸 `Response`/`any`）、类型对齐后端 schema（FE-7）；**禁 import containers/components**（逆向依赖违 ES-FE-2）；密钥经 `import.meta.env` 注入、不硬编码不入库（GEN-3）。
   - **类型层 `model/`**（无独立 Spec · 见 `specs/README.md`「≈8」口径）：TS interface/type 随 props / hook 返回 / service 出入参就近引用；金额字段整数分、字段名/单位与后端 `model/` schema 对齐（FE-7）。

3. **金额整数分整数运算**（GEN-1 / FE-2 · 权威 `项目编码规范.md §4 FE-2`）：金额/价格字段用 `priceCents: number`（最小单位分整数语义），**禁浮点存金额**（禁 `price: number = 99.99`）；折扣等用整数运算（如 `Math.floor(priceCents * discountBps / 10000)`），不向下传浮点；展示格式化（如 `formatCents`）放 `utils/`，组件内不做浮点金额运算。

4. **外部调用超时 + 降级**（GEN-2 / FE-3 / ES-FE-5 · 权威 `项目编码规范.md §4 FE-3` · `specs/04-services-external.md`）：services 层所有外部 HTTP 调用须显式设**超时**（fetch 用 `AbortController` + `setTimeout(() => ctrl.abort(), ms)`，或 axios `timeout: ms`）+ **失败降级**（超时/网络错误时返回文档化默认值如空列表/缓存/降级标记，不裸抛吞、不空 `catch {}`）；重试有限次且总时长受控，禁无界轮询。**此项违规 = 评审默认 MUST FIX**（R-002 强绑定 · 见 `项目编码规范.md §0` R-002 评审强绑定）。

5. **组件分层瘦身**（GEN-4 / FE-4 / ES-FE-1~3）：components 保持纯展示（逻辑下沉 hooks/containers、外部调用归 services）；分层单向向下不逆向（services 不 import containers/components；hooks 不 import containers）。命名约定（FE-6 / ES-FE-4）：组件 `PascalCase.tsx` / hooks `useXxx.ts` / services `xxxService.ts`；TS strict、禁 `any` 滥用（FE-1）；结构化日志、禁裸 `console` 打生产（GEN-5 / FE-6）。

6. **不过度重构 + 复用**（GEN-7）：不做超出需求范围的重构；优先复用项目内已有模块（统一 `httpClient` / `utils/` · 防熵增）。

7. **lint 静态检查**：对改动文件做静态检查（lint 工具具名实值见绑定声明 `react-vite-binding.md` 的 RequiredCommandRef · **⚠ 受控前向引用，见 §3**），消除 lint 告警；命名遵第 5 步、TS strict 遵 FE-1。本 skill 引用**抽象成员** RequiredCommandRef（执行入口 = `npx`）而非硬编码具名 lint 工具（绑定层实值待 RM-129/S-002b-FE 落地）。**绑定声明落地前的临时降级**：可用 `npx tsc --noEmit`（类型检查）+ `npx eslint --ext .ts,.tsx src/`（若项目已配 ESLint）作为 lint 兜底，直至 RM-129/S-002b-FE 完成。

8. **构建/收集校验**（绑定层「依赖装配 + 构建/收集校验」的 React+Vite 实做 · 与 S-001 vitest 门禁口径一致）：在前端业务子项目根执行——
   - `tsc --noEmit`（TypeScript 类型校验，确认无类型错误 / strict 违反）；
   - `vitest run`（用例收集 + 构建校验，确认无收集错误）。
   测试命令具名实值经绑定声明 `testCommand()`（vitest · **⚠ 受控前向引用，见 §3**）；本 skill 引用抽象成员 `testCommand()` 而非硬编码。类型/收集失败 → 回退阶段3 修复（对接 `开发流程规范.md §2.1`）。

9. **产出 `coding_report_vN.md`**：改动点 + 分层对照 + 硬约束自检（金额整数分 / 超时降级 / 组件分层瘦身 / 命名 / import 方向）+ 风险。

## 5. 产出物

- React+Vite 前端代码变更（FE 业务子项目根，以 spec 为准）；
- `../../changes/<变更目录>/coding/coding_report_vN.md`（版本递增）。

> 报告精简：本 SKILL 产出的报告类产物须满足 `plugins/harness-core/rules/开发流程规范.md` **DF-012**（内容硬约束 + 100 行软自检线 + 证据优先 + 不硬截断；`spec.md`/`tasks.md` 豁免）。

## 6. 完成判据

- `tsc --noEmit` + `vitest run` 无错（类型校验 + 用例收集/构建通过 · 第 8 步）；
- lint 改动文件无遗留告警（第 7 步）；
- 对照 4 份 FE 分层 Spec / `项目编码规范.md §4 FE` 无 MUST 违反（金额整数分 / services 超时降级 / components 纯展示瘦身 / import 单向不逆向 / 命名 / 类型对齐后端 schema）；
- `coding_report_vN.md` 齐全，交付阶段4 评审。

## 7. 引用

- 栈无关骨架：`plugins/harness-core/skills/coding-skill/`（逐层 + GEN 硬约束栈无关流程）；FE 分层 Spec 索引：`specs/README.md`（= `layeredSpecMapping()` FE 实值 · **可解析、不悬空**）。
- 绑定声明：`react-vite-binding.md`（testCommand / outputParser / RequiredCommandRef 的 vitest 实值）——**⚠ 已知受控前向引用：尚未落地**（owner 候选 RM-129〔S-001 vitest 解析器〕/ 后续 S-002b-FE 绑定卡；范围边界 ∉ 本 skill 卡 S-006a）；**阶段5 链接完整性核验豁免此受控前向引用**（悬空属预期、非缺陷）。
- 约束（what）：`plugins/harness-core/rules/项目编码规范.md §4 FE-1~7`；分层：`plugins/harness-core/rules/工程结构.md §2.4 ES-FE-1~5`。
- 下游：`plugins/harness-core/skills/code-review/`、`plugins/harness-core/skills/expert-reviewer/`（阶段4）。
