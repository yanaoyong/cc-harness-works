---
name: CLI 调用规范（文档 Wiki 模块）
scope: 文档 Wiki 模块 5 bin 的 CLI 参数面 / 退出码语义 / 仓库根直接执行约定 / 摄取安全
rule_kind: 新增模块专属 Rule（本模块 API 设计规范等价物 · 并列补充既有 HTTP API 设计规范，无覆盖、无冲突）
enforce: mechanical+manual
version: 2.0.0
updated: 2026-06-21
adr: ADR-001（CLI 参数面 + 退出码语义为契约载体，非 HTTP/OpenAPI）· ADR-005（旁路 · 复用）· ADR-009（采纳度重构 · wiki-query 单命令）
---

# 规则 · CLI 调用规范（文档 Wiki 模块 · 本模块 API 设计规范等价物 · 新增）

> **本规则为模块级新增 Rule，并列补充而非覆盖 myharness 既有面向 HTTP/FastAPI 的 API 设计规范**。本模块 = headless CLI 组件（无 HTTP 面 · ADR-001），其"API 设计规范"等价物 = **CLI 调用规范**（4 bin 的命令行参数 + 退出码语义 + 仓库根直接执行约定）。
> **声明 · 与既有 API 设计规范的关系**：myharness 既有面向 HTTP/FastAPI 的 API 设计规范（`docs/stage-02-全生命周期拓展/03-质量与改进/03-API 设计规范.md` 体系）**不受本规范影响**；本规范是本模块 **CLI 形态的并列补充**，两者各管各的契约面（HTTP 端点 vs CLI 参数面），无覆盖、无冲突。
> **承接 ADR**：ADR-001（CLI 参数面 + 退出码语义为契约载体）。真值源 = 组件实 bin（M3.2 api-design.md §2 逐字校准）。

## 0. 适用范围

适用于文档 Wiki 模块 5 个 bin（`wiki-rescan` / `wiki-lint` / `wiki-extract` / `wiki-ingest-cheap` / `wiki-query`）的 CLI 契约约束与编排方调用纪律。不适用于 HTTP/FastAPI 服务（那走既有 API 设计规范）。第五 bin `wiki-query`（仓库根直接执行的单命令查询入口 · ADR-009）的契约见 §7（CLI-008~012）。

## 1. CLI 契约总则

| 编号 | 规则 | 级别 | 校验方式 |
|---|---|---|---|
| CLI-001 | 全部脚本**在仓库根直接执行**（脚本有执行位、**无 `python3` 前缀** · C-002）；提示词/白名单引用脚本须写明"勿加 python3 前缀" | MUST 机械 | 脚本仓库根直接执行 exit 0（scope §3 定量①）|
| CLI-002 | **stdout 纯 JSON、诊断走 stderr**——编排方解析结果只读 stdout JSON，诊断信息读 stderr，互不混淆 | MUST 人工 | stdout/stderr 分离核对 |
| CLI-003 | **退出码为权威错误判定**（无头会话自述不可信 · C-005）；统一退出码语义见 §2 | MUST 机械+人工 | 退出码断言 |
| CLI-004 | `--wiki <dir>` 为 rescan/lint/extract 命令的必填参数，语义 = 指向**单一 corpus 目录**（一次只操作一个 corpus · C-010）；路径为**仓库根相对路径**（如 `--wiki wiki/`、`--wiki wiki-background/<c>/`）| MUST 人工 | corpus 路由核对（承接 M3.2 LOW-1 澄清）|

> **wiki-query 适配声明（承接 ADR-009）**：第五 bin `wiki-query` 遵循 CLI-001（仓库根直接执行 · 无 `python3` 前缀）/ CLI-003（退出码权威 · 见 CLI-009）/ CLI-004（`--wiki` 单 corpus · 仓库根相对路径 · 见 CLI-008）。**CLI-002 适配例外**：`wiki-query` stdout = **面向 agent 直接消费的答案文本**（非 JSON · 见 CLI-010），诊断仍走 stderr——这是查询命令与摄取/lint 命令（stdout JSON）的有意形态差异。CLI-006/007 正交（`wiki-query` 只读不碰 key；其内部回退 grep 须排除敏感目录 · 见 CLI-011）。

## 2. 统一退出码语义（逐字校准组件 · cross-cutting-error.md §1）

| 退出码 | 语义 | 适用脚本 |
|---|---|---|
| **0** | 成功（lint = 全绿）| 全部 |
| **1** | **`wiki-lint` 专用「门禁未过」信号**（stdout JSON `checks[]` 列具体违规门禁）；其他脚本无此语义 | 仅 `wiki-lint` |
| **2** | 参数错误 / 环境缺失（如 state 不存在、互斥子命令、已有未提交批次、forget 文件仍存在、无密钥环境变量、扩展名不支持）| 全部 |
| **5** | 内部错误（抽取失败等）| rescan/lint/extract |
| **6** | 能力缺失（如 `pdftotext` 不可用 · 诚实报错）| 仅 `wiki-extract` |
| 透传 | `wiki-ingest-cheap`：除 exit 2（参数/环境）外，**其余透传底层 claude 退出码**（0 即成功）| 仅 `wiki-ingest-cheap` |
| 0/2/5 | `wiki-query`：成功外形恒 **0**（命中或内部回退 grep 均 0 · 失败软化）/ **2** 参数错误（空问题 / 非法选项 / `--wiki` 指向不存在 corpus）/ **5** 退化内部错误；**不使用 exit 1**（exit 1 是 `wiki-lint` 专用门禁信号 · 见 CLI-009）| 仅 `wiki-query` |

| 编号 | 规则 | 级别 | 校验方式 |
|---|---|---|---|
| CLI-005 | 编排方据退出码处置：`wiki-lint` exit 1 → 回喂 JSON 修复重跑（不 commit）；exit 0 才 `--commit-batch`；exit 2 → 修正参数/补环境；exit 5 → 排查组件内部；exit 6 → 能力缺失诚实报错（本轮 extract N/A · O-007）| MUST 人工 | 退出码处置核对 |

## 3. 各 bin 参数面契约（校准自 M3.2 api-design.md §2）

> 仅登记契约面要点（完整逐子命令表见 m3.2 api-design.md §2，本规范不复制全表，避免双源漂移）。

| bin | 契约面要点 | 锚点 |
|---|---|---|
| `wiki-rescan` | 互斥子命令（`--init`/`--begin-batch`/`--commit-batch`/`--forget`/`--set-ext` 五者互斥）；新鲜度判据 = git diff 收窄候选 + SHA256；出 changed/new/deleted 清单；每批 ≤5 源 | api-design §2.1 |
| `wiki-lint` | 六门禁（`wikilinks`/`orphans`/`frontmatter`/`coverage`/`log`/`reviews`）；退出码权威；对 `status: open` review 放行（绿≠无待裁决矛盾）| api-design §2.2 |
| `wiki-extract` | 非 .md 源抽取 → `_meta/extracted/`；**本轮 N/A**（O-007 · 全 .md · C-009）| api-design §2.3 |
| `wiki-ingest-cheap` | DeepSeek 无头摄取 wrapper；摄取所需 API key 经**环境变量**注入（缺 → exit 2）；`--allowedTools` 收窄（`Read,Glob,Grep,Write,Edit` + 白名单脚本 · 不给网络/不给任意 Bash）；摄取自述不作判据 | api-design §2.4 |
| `wiki-query` | 单命令查询入口（命令内部承担 index→rg→两跳→断链回退 + 失败软化 + 在band 提示）；签名 `wiki-query "<问题>" [--wiki <dir>] [--budget <chars>] [--no-fallback]`；stdout = 答案文本三要素（非 JSON · CLI-002 适配例外）；退出码 0/2/5（不用 1）| §7（CLI-008~012）|

## 4. 安全约束（对齐既有 R-005/CODE-005）

| 编号 | 规则 | 级别 | 校验方式 |
|---|---|---|---|
| CLI-006 | 摄取所需 API key **只进进程环境变量、不入库**（不写 URL/stdout/日志/文件/提示词 · 对齐既有 R-005/CODE-005）；按调用切换、不动全局 | MUST 机械 | secret 扫描 + git diff 无 key |
| CLI-007 | 摄取会话工具面收窄：`--allowedTools` 只放行 `Read,Glob,Grep,Write,Edit` + 两个白名单脚本（`wiki-lint`/`wiki-rescan`），**不给网络、不给任意 Bash** | MUST 人工 | 评审（wrapper `--allowedTools` 核对）|

## 5. 与既有 API 设计规范的边界声明（不冲突）

| 维度 | 既有 HTTP API 设计规范 | 本 CLI 调用规范 |
|---|---|---|
| 契约面 | HTTP 端点 / REST / OpenAPI yaml | CLI 参数面 + 退出码 + stdout(JSON)/stderr |
| 校验工具 | schemathesis / swagger 等 | shell 退出码断言（ADR-001） |
| 适用对象 | FastAPI 业务服务（demo/harnessdemo）| 文档 wiki 组件 4 bin |
| 关系 | **并列** | **并列补充**（无覆盖 · 无冲突 · ADR-001） |

## 7. `wiki-query` CLI 契约（CLI-008~012 · 第五 bin · 承接 ADR-009 · 校准自 api-design §3）

> 把 api-design §3 的 `wiki-query` CLI 契约（签名/选项/退出码/输出三要素/失败软化）固化为本规范新增 CLI-008~012 段；与既有 CLI-001~007 并列、不改既有四脚本（本段为 CLI 规范新增段，git diff 仅新增 CLI-008~012；命令本体已物理存在于 `.harness/components/wiki-engine/bin/wiki-query`）。

### 7.1 命令签名（CLI-008）

```
wiki-query "<问题>" [--wiki <dir>] [--budget <chars>] [--no-fallback]
```

| 编号 | 规则 | 级别 | 校验方式 |
|---|---|---|---|
| CLI-008 | **`wiki-query "<问题>"` 单命令** = 文档 Wiki 模块第五 bin（仓库根直接执行 · 有执行位 · 无 `python3` 前缀 · CLI 规范 git diff 仅新增 CLI-008~012 段不改既有四脚本契约）；位置参数 `<问题>`（必填 · 空 → exit 2）；选项 `--wiki <dir>`（corpus 路由 · 默认 `wiki/` · 仓库根相对路径 · 单 corpus 语义对齐 CLI-004）/ `--budget <chars>`（输出字符预算上限 · 默认值实测校准 · 不写死数字）/ `--no-fallback`（关命令内部 grep 回退 · 仅诊断/测试用 · 默认不带=回退开）| MUST 机械 | 仓库根直接执行 exit 0 |

### 7.2 输出三要素（CLI-010）

> `wiki-query` 返回文本（stdout · 面向 agent 直接消费 · **非 JSON**）按三要素组织：① wiki 命中段（第一跳命中页路径 + 第二跳页正文引源路径 + 命中页正文 · 输出做全非半截）/ ②（未覆盖/断链时）grep 回退段（标注头 + grep 原文命中片段 `filePath:line` + 上下文）/ ③ 在band 提示语（返回文本末尾 · 命中/回退两态各对应语义）。

| 编号 | 规则 | 级别 | 校验方式 |
|---|---|---|---|
| CLI-010 | `wiki-query` stdout = **答案文本三要素**（① 两跳引用 + 命中页正文〔输出做全·非半截〕 ② 未覆盖/断链时 grep 回退段〔两段标注清晰可辨〕 ③ 返回文本末尾自带在band 提示语〔命中/回退两态各对应语义〕）；三要素结构**不被 `--budget` 裁掉**（裁剪只截尾部低相关页正文，不腰斩高相关页/不删命中段+提示）。CLI-002 适配例外：`wiki-query` stdout 是答案文本（agent 读答案而非结构化数据），**不强制纯 JSON**，诊断仍走 stderr | MUST 人工 | 命中查询断言三要素在场 + 多页命中断言 ≤ budget 且命中段+提示在场 |

### 7.3 失败软化 + 退出码（CLI-009 + CLI-011 + CLI-012）

| 退出码 | 语义 | 编排方处置 |
|---|---|---|
| **0** | 成功外形（**命中或 grep 回退均 0** · 失败软化）| 直接消费返回文本（命中段/回退段 + 在band 提示）|
| **2** | 参数错误（空问题 / 非法选项 / `--wiki` 指向不存在的 corpus 目录）| 修正调用参数（对齐既有四 bin "2 参数错误"体例）|
| **5** | 内部错误（退化兜底 · 如 corpus 目录与 rg 回退底座均不可用）| 罕见 · 排查组件内部（常态查询永远 0）|

| 编号 | 规则 | 级别 | 校验方式 |
|---|---|---|---|
| CLI-009 | **`wiki-query` 退出码 = 失败软化体现**：成功外形恒 **exit 0**（命中或内部回退 grep 均 0）；**`wiki-query` 不使用 exit 1**（exit 1 是 `wiki-lint` 专用门禁信号 · 查询无门禁语义）；"wiki 未覆盖"**不是错误**（是正常回退分支 · exit 0 · 用输出段标注区分命中/回退，而非退出码报错）；exit 2 仅参数错误 / exit 5 仅退化内部错误。**永不 isError / 永不空落**——日常路径任意查询 `exit 0 ∧ stdout 非空`；`--no-fallback` 诊断模式未覆盖时不回退但仍 `exit 0 ∧ stdout 含"无命中（--no-fallback 诊断模式）"显式标注`（非裸空、非 isError）| MUST 机械 | 故意构造未覆盖查询断言 exit 0 ∧ stdout 含 grep 回退段；诊断模式断言 exit 0 ∧ "无命中"标注 |
| CLI-011 | **命令内部回退 grep 不越权扫敏感目录**（安全 NFR③）：回退 grep 范围 = 被路由 corpus 对应源域（默认 `wiki/` → 项目源域 · `--wiki wiki-background/<c>/` → 对应背景源域）；**必须排除敏感目录**（key/凭据/`.git` 内部/环境配置等）——具体 deny-list 实测落点归后续校准卡，本规范钉死"回退不得越权扫敏感目录"原则 | MUST 人工 | 构造含敏感目录回退场景，断言回退命中不含敏感目录路径 |
| CLI-012 | **失败软化只兜"wiki 覆盖但未命中"，不兜"路径不存在"**：① `--wiki` 指向**存在的 corpus** 但查询未命中/两跳断链 → 失败软化回退 grep · **exit 0**；② `--wiki` 指向**不存在的 corpus 目录**（路径本身不存在）→ **exit 2 参数错误诚实报错**（坏路径 = 参数错误，非 wiki 没答案 · 守"不静默假阴"）；③ 背景库缺位的**优雅降级在消费方纪律层**——strategist/reviewer 调 `wiki-query --wiki wiki-background/<c>/` 拿 exit 2 时解读为"该背景 corpus 不可用 → 跳过背景查询、阶段照常推进、不阻断"（命令诚实报 exit 2，降级判断在消费方 · 承接 WK-B2）| MUST 人工 | 不存在 corpus 断言 exit 2；消费方降级纪律对照检查 |

### 7.4 旁路定性（复用 ADR-005 · 不新立）

- `wiki-query`（含内部回退 / 在band 提示）**不出现在任一阶段门禁判定式**、**无强制 hook 逼调**——旁路定性复用 ADR-005，本规范不另立。
- 退出码是查询结果的客观判定（agent/编排方据此消费），**非门禁裁决信号**（与既有 10 阶段/元流程门禁解耦 · ADR-005）。

## 8. 例外与豁免

- 本规范为模块专属新增 Rule，与既有 API 设计规范并列；任何偏离须在卡收尾 `summary.md` 例外区登记理由与影响面。
