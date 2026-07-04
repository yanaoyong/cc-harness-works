---
name: API设计规范
scope: 声明式契约编写规范（栈绑定层 / PluginManifest / hook 事件 / ResidentContract / 模板导出）
enforce: mechanical+manual
l1_resident: false
version: 1.0.0
updated: 2026-06-27
customized_from_template_version: N/A（新增 · stage-01 rules 无 API 设计规范）
flow_instance: proj-module-fullstack-plugin-20260627
spec: docs/stage-02-全生命周期拓展/02-体系设计/10-定制 Rules 沉淀与覆盖机制.md
stack: 通用（Harness-as-product 声明式契约 · 栈无关 · 非业务 HTTP API）
derives_from: [ADR-001, ADR-002, ADR-003, m3.2_interface/api-design.md, m3.2_interface/cross-cutting-auth.md, m3.3 API设计规范.md（DRAFT）]
---

# 规则 · API 设计规范（Harness-as-product 契约编写规范）

> **本系统无 HTTP/REST/GraphQL/RPC 服务面**（api-design.md §0 显式 N/A）。本规范的「API」= Harness 作为「方法论脚手架 + Claude Code plugin」产品对外暴露的**声明式契约**。规范对象 = 五类契约的**编写规范**：① 栈绑定层契约 ② PluginManifest ③ hook 事件契约 ④ ResidentContract 注入契约 ⑤ 模板导出契约。
> **落地说明（M4）**：本文由 M3.3 API 设计规范设计稿物理落地为正式 Rules（C-3 单源 · 设计记录保留于 m3.3_customization/rules/ DRAFT）。本规范为**按需加载（L2）**契约编写规则，非 L1 常驻。

## 0. 适用范围

适用于本仓所有**声明式契约**的编写：StackProfile 绑定声明、plugin.json manifest、hook 配置、常驻契约注入载体、模板导出。不约束业务 HTTP API（本系统无此面 · 显式 N/A）。机器可校验等价物 = JSON-Schema 草稿 + 声明式接口表 + 输出解析器单测 + 产物 grep 断言（替代 OpenAPI）。

## 1. 栈绑定层契约规范（BindingLayerContract · AGG-1 · ADR-003）

> （溯源 · RM-2026-127 / S-002a：流程层 6 skill 去栈特定串使本契约三成员抽象签名〔`testCommand`/`outputParser`/`layeredSpecMapping`〕成为流程层唯一依赖面 · 契约定义权威源仍在 `proj-module-fullstack-plugin-20260627/m3_architecture/m3.2_interface/api-design.md §1.1`，此处仅追加溯源锚注、不重定义判定语义 C-3 单源）

| 编号 | 规则 | 级别 | 校验方式 |
|---|---|---|---|
| API-BL-1 | 每个技术栈 = 一份 StackProfile 声明，须含三成员：`testCommand()→CommandSpec{cmd,args,cwd}` + `outputParser(rawStdout,exitCode)→{exit,total,passed}` + `layeredSpecMapping()→SpecLayer[]` | MUST 人工 | 评审 + profile 加载校验 |
| API-BL-2 | **GateContract 判定式 `exit==0 && total>0 && passed==total` 跨所有 profile 恒等**——profile 只换 testCommand/outputParser，不换判定本质（C-5 / S-001） | MUST 机械 | 双向校验：Python 用例 stdout + FE vitest stdout 各喂 parser 套同一判定式（BL-INV-1）|
| API-BL-3 | `outputParser` 解析失败须**显式报错**，不得静默置 0（防假绿 total=0 误判） | MUST 机械 | 解析器单测（异常路径覆盖）|
| API-BL-4 | 流程层契约消费方只依赖绑定层**抽象签名**，**零栈特定串**（`pytest`/`vitest`/`ruff`/`FastAPI` 等不得出现在流程层文件） | MUST 机械 | grep 流程层文件基线为空（BL-INV-2）|
| API-BL-5 | `RequiredCommandRef` 声明须与 profile 实调命令一致（python→python3·ruff / react-vite→npx），不声明幽灵依赖 | MUST 人工 | 评审比对 |

## 2. PluginManifest 编写规范（plugin.json · AGG-2 · S-011 · CL-05）

| 编号 | 规则 | 级别 | 校验方式 |
|---|---|---|---|
| API-PM-1 | `plugin.json` 须通过 JSON-Schema（draft-07）校验；`name` 为 kebab-case（`^[a-z0-9]+(-[a-z0-9]+)*$`） | MUST 机械 | manifest lint / schema 校验（PM-INV-1）|
| API-PM-2 | **9 类组件资产字段映射完整**：commands / agents / skills / hooks / mcpServers / outputStyles / lspServers / experimental.themes / experimental.monitors——空字段须声明在场（空对象/空数组），履行映射完整、不声明幽灵能力 | MUST 机械 | schema 校验 + 字段在场检查（S-011 验收⑤）|
| API-PM-3 | `requiredCommands` 与实际依赖一致：harness-core=`git` / profile-python=`python3,ruff` / profile-react-vite=`npx`（无幽灵依赖） | MUST 人工 | 解析 skill/hook 实调命令比对（PM-INV-2）|
| API-PM-4 | **版本双轨**（CL-03）：对外稳定轨写显式 semver `"version":"x.y.z"`；内部快速轨省略 version 字段回落 commit-SHA（每 commit 计新版）。无 lockfile——plugin 间依赖经 `dependencies` 字段声明 semver 约束（如 `~2.1.0`） | MUST 人工 | 评审（版本策略一致性）|
| API-PM-5 | **manifest 无状态铁律**：manifest 不得含写项目目录的声明（写盘走 hook · 见 §3）；plugin 装只读 cache（C-7 · ADR-001 M-7） | MUST 人工 | 评审：manifest 内无写项目目录声明（PM-INV-3）|
| API-PM-6 | 附带 `settings.json` 仅可用 `agent` / `subagentStatusLine` 两 key（CL-05）——**不得用于规则/memory/context 注入**；规则注入走 skill 或 SessionStart hook（§4） | MUST 人工 | 评审（settings.json key 白名单）|
| API-PM-7 | 权限默认只读 opt-in：写文件/命令执行/网络出域能力须经 `settings.json` permissions 段显式声明（最小权限 · NFR-安全-2 · cross-cutting-auth T-2） | MUST 人工 | 评审（权限声明面）|

## 3. hook 事件契约规范（event-contracts · ADR-002 桥载体 · CL-04/CL-05）

| 编号 | 规则 | 级别 | 校验方式 |
|---|---|---|---|
| API-HK-1 | hook 退出码语义恒定：维护型 hook（SessionEnd 维护 / wiki·cg sync）exit 0 **永不阻断主流程**（旁路 · ADR-005 · C-2）；注入型 hook（SessionStart stdout 注入 / UserPromptSubmit prompt_state）stdout 即注入载荷 | MUST 机械+人工 | hook 单测（退出码）+ 评审 |
| API-HK-2 | **无 PostInstall 假设**（CL-04）：任何「安装后一次性动作」（脚手架落盘）须经 SessionStart hook diff 探测实现（`${CLAUDE_PLUGIN_DATA}` first-run 等价模式），不得假设存在安装后钩子 | MUST 人工 | 评审（无 PostInstall 引用）|
| API-HK-3 | SessionStart 注入型 hook 须控制注入开销：注入常驻契约**精简可重建子集**而非全文（NFR-性能-1 · ADR-002 后果）| SHOULD | 评审（注入体积自检）|
| API-HK-4 | hook 配置经 manifest `hooks` 字段声明；事件名须在官方 hook 事件表内（不发明非标准事件 · 防 schema 时效性踩坑） | MUST 人工 | 评审（事件名核对官方快照）|

## 4. ResidentContract 注入契约规范（AGG-5 · ADR-002 · S-013）

| 编号 | 规则 | 级别 | 校验方式 |
|---|---|---|---|
| API-RC-1 | `InjectionPath` 取值 ∈ `{project-CLAUDE.md, sessionstart-hook, skill-invoke}`（CL-05 唯二 plugin 注入路径 + 项目 CLAUDE.md），不得引入第四路径 | MUST 机械 | 枚举校验（RC-INV-3）|
| API-RC-2 | **会话宪法本体必经 `project-CLAUDE.md` 载入**（C-4 · CL-01 plugin 根 CLAUDE.md 不载入）；hook/skill 注入的是会话宪法**可重建子集**，不取代权威源 | MUST 人工 | 评审 + 行为验收（RC-INV-1）|
| API-RC-3 | plugin 形态下第一动作契约/身份/委派纪律须**可重建为常驻路径**——**行为验收 dogfood**：触发首条代码改动请求，首条响应仍走第一动作契约（不靠静态文案 · S-013） | MUST 人工 | dogfood 行为验收（RC-INV-2）|
| API-RC-4 | 注入机制选型遵 ADR-002（hook 为主 + skill 降级 · HITL-M3 待确认）；改选须经 ADR 演进 | MUST 人工 | 评审（与 ADR-002 一致）|

## 5. 模板导出契约规范（TemplateExport · AGG-4 · S-008）

| 编号 | 规则 | 级别 | 校验方式 |
|---|---|---|---|
| API-TE-1 | 导出产物不含 `changes/` 历史实例与 demo/harnessdemo/test 噪音；保 `_TEMPLATE` + `.harness/{skills,rules,agents,components}` | MUST 机械 | 导出后 grep 历史卡/对比代码为空（TE-INV-1 · S-008）|
| API-TE-2 | 分层入口三档 `tier ∈ {thin,medium,thick}`：thin = 起新项目立即可用最小集（核心骨架 + 10 阶段 + 单 profile + TEMPLATE-USAGE + downloadableManifest） | MUST 人工 | 人工核对 + manifest 与实际可下发集一致（TE-INV-3）|
| API-TE-3 | wiki index 重建后 `wiki-lint` exit 0（无悬挂链接） | MUST 机械 | wiki-lint（TE-INV-2）|

## 6. C-1 厂商隔离自检（铁律）

- 本规范全程**零具体外部检索引擎/后端专名**：research-discovery 仅以抽象 skill 名出现；密钥/出域只以「厂商层引擎 API key」类目表述（cross-cutting-auth K-1 同口径）。
- 信任/权限/密钥契约为**安全语义**，**不进任一阶段门禁判定式**（C-2 旁路语义）。

## 7. 正例 / 反例

- 正例：新增 Go 栈 = 加一份 StackProfile（go testCommand + 解析器 + 分层映射）+ 一个 profile plugin，核心流程层 0 改动（API-BL-4 + ADR-003）。
- 反例：在流程层 unit-test-ci skill SOP 内写死 `pytest -q`（违 API-BL-4 零栈特定串）。
- 反例：manifest 省略 `mcpServers` 字段（违 API-PM-2 九字段映射完整——空也须声明在场）。
- 反例：用 plugin 附带 settings.json 注入规则文本（违 API-PM-6——settings.json 仅 agent/subagentStatusLine 两 key）。
- 反例：把脚手架落盘寄望于 PostInstall 钩子（违 API-HK-2——官方无此钩子，须 SessionStart diff）。
- 反例：API 规范点名某具体外部检索引擎/后端专名（违 §6 C-1 铁律——本卡 M3.2 已因点名被 MUST FIX，勿复发）。
