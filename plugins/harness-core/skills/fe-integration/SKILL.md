---
name: fe-integration
description: 按需 Skill。处理前后端联调期对接问题（Q9 ε-3），按三类硬条件触发收敛。
trigger_phase: on-demand
trigger: 联调期前端报告对接问题 · ad-hoc/fix 卡显示是契约级问题
inputs: 当前变更目录、API 设计规范.md（M3.3 产物）、前端报告的对接问题材料
outputs: 当次变更目录 integration/ 三件套（contract-mismatch.md、handoff-doc.md、integration-checklist.md）
version: 2.0.1
updated: 2026-07-02
spec: docs/stage-02-全生命周期拓展/02-体系设计/08-Skills 扩展规范（含 fe-integration）.md
---

# Skill · 前后端联调（fe-integration）

## 1. 目的
处理前后端联调期对接问题（Q9 ε-3）：记录契约不一致、按 Q8.3 HITL 分流归因，并产出交付前端的对接文档与联调清单，使对接表面文档化、问题处置可追踪。

## 2. 触发条件
**按需**（on-demand）：联调期前端报告对接问题 · ad-hoc/fix 卡显示是契约级问题（08 §2 表该行口径）。具体触发判定遵循以下**三段收敛口径**（权威对照：`docs/stage-02-全生命周期拓展/03-质量与改进/02-契约测试与前后端联调规范（Q9 落地）.md` §4.1）：

1. **默认（不触发）**：阶段 4 评审发现的契约违反 → 走 Reviewer MUST FIX 回阶段 3 修复，**不调用本 Skill**。
2. **触发 3 类硬条件**（任一满足才触发）：
   - ① **联调期前端报告对接问题**（实际对接不一致）——前端调用后端发现字段缺失/类型不符/错误码无法处理等实测不一致，非纯文档/spec 层面；**执行路径**：执行 §4.1 联调执行流程 → 发现不一致 → 执行 §4.3 不一致收敛路径（记录 → 分流 → 修复 → 回写）；
   - ② **需要产出 handoff-doc 交付前端**——即使无 bug，也需文档化对接表面给前端（如新增 API 上线前发布对接说明）；**执行路径**：执行 §4.1 联调执行流程（即使无 bug）→ 按 §4.2 契约验证清单逐项核对 → 产出 handoff-doc.md 交付前端；
   - ③ **需要 Q8.3 HITL 分流 B/C 类**——通过 HITL 分流识别为 B 类（spec 问题）/ C 类（架构问题），需要触发模式 E 而非走 fix 卡；**执行路径**：记录 contract-mismatch.md（status: open）→ 执行 §4.3 HITL 分流（A/B/C）→ 触发对应修复路径（A → fix 卡 / B/C → 模式 E REOPEN）。
3. **判断顺序**：先尝试「Reviewer MUST FIX 回阶段 3」（默认路径）→ 不适用再依次判断上述 3 类硬条件 → 仍不适用则非本 Skill 范畴，走对应其他路径（如 fix 卡走 Q8.3 默认 A 类）。

## 3. 输入
- 当前变更目录（当次联调所属的 10 阶段变更实例）；
- `API 设计规范.md`（M3.3 产物，契约判定权威）；
- 前端报告的对接问题材料（实测请求/响应样本、错误现场等）。

## 4. 步骤（SOP）

### 4.1 联调执行流程

**前置条件**：触发条件①②③之一满足（见 §2）；前后端代码已部署可联调环境（本地 dev / staging）。

**步骤**：

1. **前端发起调用**（执行者：前端 / Owner 模拟前端）
   - **输入**：API endpoint（如 `GET /api/v1/users`）、测试数据（从 spec 消费方契约段获取）
   - **执行**：使用浏览器 DevTools / Postman / curl 发起 HTTP 请求
   - **输出**：实际响应（status code / headers / body）、DevTools Network 面板截图或 curl 原始输出
   - **验收**：能拿到后端响应（无论成功/失败），响应已记录

2. **后端响应接收与日志检查**（执行者：后端 / Owner）
   - **输入**：前端实际请求记录（从步骤1获取）
   - **执行**：检查后端日志（如 FastAPI 控制台输出 / 应用日志）确认请求已到达、处理逻辑已执行
   - **输出**：后端日志片段（含请求路径 / 参数 / 响应状态码）
   - **验收**：后端确认收到请求、已处理、已返回响应

3. **契约验证**（执行者：Owner，对照 §4.2 契约验证清单）
   - **输入**：实际响应（步骤1）+ `API 设计规范.md`（契约权威）+ spec 消费方契约段
   - **执行**：对照 §4.2 契约验证清单逐项核对（字段命名 / 错误码 / 响应结构 / 金额单位 / CORS / 认证鉴权 / 时间格式）
   - **输出**：契约验证结果（通过项 / 不一致项，记入 `integration/integration-checklist.md`）
   - **验收**：所有契约项已逐项核对，不一致项已记录

4. **结果记录与分流**（执行者：Owner）
   - **输入**：契约验证结果（步骤3）
   - **执行**：
     - 若**无不一致**：记录 `integration/integration-checklist.md` 全部通过 → 产出 `handoff-doc.md` 交付前端（触发条件②路径）。handoff-doc.md 内容至少包含：接口路径 / 请求方法 / 参数说明 / 响应结构示例 / 已验证契约项清单（引用 integration-checklist.md）
     - 若**有不一致**：记录 `integration/contract-mismatch.md`（status: open）→ 执行 §4.3 不一致收敛路径（触发条件①③路径）
   - **输出**：三件套之一或全部（contract-mismatch.md / handoff-doc.md / integration-checklist.md）
   - **验收**：不一致已记录或无不一致已确认，进入对应后续路径

### 4.2 契约验证清单

**权威源**：`.harness/rules/API设计规范.md`（M3.3 产物）全部条款。本清单采用"引用 + 验证步骤"模式：默认引用 API 设计规范，只在此列出具体验证步骤。

**验证项**（逐项对照实际响应）：

1. **字段命名约定**（通过条件：所有字段符合 snake_case，如 `user_id` / `created_at`）
   - 验证方式：遍历响应 JSON 所有键，检查是否全小写 + 下划线分隔
   - 不通过示例：`userName`（驼峰）/ `user-id`（短横线）

2. **错误码格式**（通过条件：错误响应含 `error_code` / `message` / `trace_id` 字段）
   - 验证方式：触发一个已知错误场景（如 404 / 400 参数错误），检查响应结构
   - 不通过示例：缺 `trace_id` 字段 / 错误码非注册表内值

3. **响应结构**（通过条件：字段类型 / 必填性符合 spec 消费方契约段）
   - 验证方式：对照 spec 消费方契约段逐字段核对（如 `price_cents: int` 必填）
   - 不通过示例：必填字段缺失 / 类型不符（期望 int 实际 string）

4. **金额单位跨栈一致性**（通过条件：BE 金额字段为 int（分，如 `price_cents: int`），FE 对应字段整数分语义（`priceCents: number`，无浮点）；字段名/类型/单位跨栈一致（GEN-1/FE-7））
   - 验证方式：对照 BE Pydantic schema 金额字段 + FE `model/` 下对应 TS interface，确认均为整数分单位，不出现 `price: number = 99.99` 式浮点金额
   - 不通过示例：FE 端 `price: number = 99.99`（浮点元）/ BE `price_cents` 与 FE `price` 单位不一致（分 vs 元）

5. **CORS 头**（通过条件：响应含 `Access-Control-Allow-Origin` 等 CORS 头，如跨域调用适用）
   - 验证方式：前端跨域调用时检查 DevTools Network 面板 Response Headers
   - 不通过示例：跨域请求被浏览器拦截（CORS error）

6. **认证/鉴权头格式**（通过条件：需认证接口的请求/响应头符合规范，如 `Authorization: Bearer <token>`）
   - 验证方式：需认证接口发起请求时检查请求头格式、未授权响应返回 401 + 明确错误码
   - 不通过示例：未授权返回 403 而非 401 / 错误信息不明确

7. **时间格式**（通过条件：时间字段符合 ISO 8601 格式，如 `2026-06-28T10:30:00Z`）
   - 验证方式：检查响应中所有时间字段格式（如 `created_at` / `updated_at`）
   - 不通过示例：时间戳（epoch 秒）/ 非 ISO 格式字符串

8. **性能要求**（通过条件：响应时间符合 spec 消费方契约段或 M3.2 QAS 定义；若 spec 消费方契约段未定义性能要求，本项标记 N/A（不适用））
   - 验证方式：记录多次调用的响应时间（DevTools Timing 面板 / curl `-w` 选项），取 P95
   - 不通过示例：P95 响应时间超出 spec 约定阈值

9. **降级行为**（通过条件：外部依赖失败时，接口能降级返回（如缓存 / 默认值），不 500；若接口无外部依赖，本项标记 N/A）
   - 验证方式：模拟外部依赖失败（如断网 / 关闭下游服务），检查接口响应
   - 不通过示例：外部依赖失败导致接口 500 / 无降级提示

**验证记录**：将每项验证结果记入 `integration/integration-checklist.md`（通过 ✅ / 不一致 ❌ + 描述）。

### 4.3 不一致收敛路径

**触发**：§4.1 步骤4 或 §4.2 验证发现不一致。

**步骤**：

1. **发现不一致**（执行者：Owner，来源：§4.1 实测 / §4.2 契约验证 / 阶段4评审外的其他渠道）
   - **输入**：不一致现象（实际响应 vs 期望契约）
   - **执行**：确认不一致确实存在（非误判），记录现象 + 期望
   - **输出**：不一致现象描述（准备记入 contract-mismatch.md）

2. **记录到 contract-mismatch.md**（执行者：Owner）
   - **输入**：不一致现象（步骤1）
   - **执行**：在 `integration/contract-mismatch.md` 创建新条目（schema 见下方或 Q9 §4.3），`status: open`
   - **输出**：`integration/contract-mismatch.md` 已记录（含 frontmatter status: open + 现象 + 期望段）
   - **验收**：条目已落盘，status 为 open

3. **HITL 分流**（执行者：Owner 发起，人工拍板）
   - **输入**：contract-mismatch.md 记录的不一致（步骤2）
   - **执行**：按 Q8.3 HITL 分流问询（A 实现 / B spec / C 架构）拍板归因
   - **输出**：归因结果（A / B / C）+ 理由
   - **验收**：归因已拍板，回写 contract-mismatch.md `attribution` 字段 + `status: triaged`

4. **下游修复路径分流**（执行者：Owner，根据步骤3归因结果）
   - **A 类（实现问题）**：新建 `fix-<slug>-<date>` 10 阶段卡，`bug_class: implementation`，`parent_change_dir: <当前卡>`；fix 卡走完整 10 阶段修复
   - **B 类（spec/需求/契约问题）**：触发模式 E（按 Q8 §4.6 统一映射表：B1 需求/范围 → REOPEN M1/M2 · B2 接口契约 → REOPEN M3 起点 M3.2——联调语境多为 B2）+ 级联评估（Q6）
   - **C 类（架构问题）**：触发模式 E REOPEN M3（修订起点按 Q8 §4.6 由 HITL 确认 M3.1/3.2/3.3）+ 级联评估
   - **输出**：下游修复卡已创建（A 类）或模式 E 已触发（B/C 类），记 contract-mismatch.md `related_card` 字段

5. **下游修复完成后回写状态**（执行者：Owner，触发：下游修复卡 PASSED 或模式 E 修订 PASSED）
   - **输入**：下游修复卡 summary.md（总体状态 PASSED）或模式 E 修订完成记录
   - **执行**：回写 contract-mismatch.md `status: resolved`，`resolved_at: <ISO 日期>`
   - **输出**：contract-mismatch.md 终态（status: resolved）
   - **验收**：DASHBOARD 联调追踪段不再显示该条目（已关闭）

**contract-mismatch.md schema**（权威源：Q9 §4.3，此处指针引用）：

```markdown
---
status: open / triaged / resolved / wont-fix
attribution: implementation / spec / arch
related_card: <change_dir>
opened_at: <ISO 日期>
resolved_at: <ISO 日期 · 可选>
---

# 契约不一致：<简短标题>

## 现象
<前端实际遇到的问题>

## 期望
<按 API 设计规范.md 应当的表现>

## 归因（HITL 分流 · Q8.3）
- A · 实现问题 · 走 fix-<...> 10 阶段
- B · 需求/范围/契约层问题 · 触发模式 E（按 Q8 §4.6 统一映射表：B1 需求/范围→REOPEN M1/M2 · B2 接口契约→REOPEN M3，修订起点 M3.2——联调语境多为 B2）
- C · 架构问题 · 触发模式 E REOPEN M3（修订起点按 Q8 §4.6 由 HITL 确认 M3.1/3.2/3.3）

## 解决方案
<拍板后的处理路径>
```

## 5. 产出物
当次变更目录 `integration/` 子目录三件套（与 08 §2 表「产出位置」列一致）：
- `../../changes/<变更目录>/integration/contract-mismatch.md`（记录契约不一致）
- `../../changes/<变更目录>/integration/handoff-doc.md`（交付给前端的对接文档）
- `../../changes/<变更目录>/integration/integration-checklist.md`（本次联调对接清单）

**与 DASHBOARD 联动**：未关闭的 contract-mismatch（`status != resolved && status != wont-fix`）显示在 `project/DASHBOARD.md`「联调追踪」段；数据源为扫描各变更目录 `integration/contract-mismatch.md` 头部 `status` 字段（Q9 落地文档 §5）。

## 6. 完成判据
- 契约不一致已分流：`contract-mismatch.md` 各条目归因（A/B/C）已经 HITL 拍板，`status` 至少为 `triaged`；
- 对接文档已交付前端：`handoff-doc.md` 已产出并交付；
- checklist 已确认：`integration-checklist.md` 各项已勾选或例外项已留痕；
- 本次产物若进入评审环节，须 Reviewer 评审通过（`APPROVED`，或 `APPROVED_WITH_CONDITIONS` 经 Owner 核验条件闭合，见 `../../rules/开发流程规范.md` DF-002 注记）——评审机制仅指针引用 `../expert-reviewer/SKILL.md`（现行版为准），不在此复制其内部分档/清单细节。

## 7. 引用
- **执行者**：本 Skill 为按需 Skill，由编排中枢 Owner 按 §2 触发收敛口径调度（与 09 §2 角色矩阵一致；元流程 M 阶段 Skill 的执行者为 strategist 子 Agent，本 Skill 不在其列）。
- 触发收敛/产出物 schema/Q8.3 联动权威：`docs/stage-02-全生命周期拓展/03-质量与改进/02-契约测试与前后端联调规范（Q9 落地）.md`（§4 触发与三件套与分流联动、§5 DASHBOARD 联调追踪）。
- 骨架来源：`docs/stage-02-全生命周期拓展/02-体系设计/08-Skills 扩展规范（含 fe-integration）.md` §3.9。
- 评审：`../expert-reviewer/SKILL.md`（指针引用，现行版为准）。
