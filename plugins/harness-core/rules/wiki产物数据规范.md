---
name: Wiki 产物数据规范
rule_kind: 新增模块专属 Rule
scope: 文档 Wiki 产物（Page / _meta/state.json / log.md / reviews.md）数据载体 schema
enforce: mechanical+manual
l1_resident: false
version: 1.0.0
updated: 2026-06-15
承接: ADR-003（git 仓内纯 markdown 而非 DB）
---

# 规则 · Wiki 产物数据规范（数据载体 schema · 新增模块专属 Rule）

> **本规则为模块级新增 Rule，不覆盖 myharness 既有 `.harness/rules/` 四件套**（工程结构 / 开发流程规范 / 项目编码规范），与之并列不冲突。承接 M3.2 数据架构三视图（data-storage-choice.md §2 各载体 schema + data-lifecycle.md + cross-cutting-observability.md §1）+ M3.1 domain-aggregates.md 聚合根。
> **核心数据原则**：**git 即事实源**（ADR-003）——所有产物 = git 仓内纯 markdown + 单 `state.json` 状态文件，无 DB；schema 与 `wiki-lint` 六门禁绑定（页面模板硬要求）。
> **承接 ADR**：ADR-003（git 仓内纯 markdown 而非 DB）。schema 逐字校准组件 `references/schema.md` + bin 实现（不臆造字段）。

## 0. 适用范围

适用于文档 Wiki 产物（每个 corpus 目录内的 Page / `_meta/state.json` / `log.md` / `reviews.md`）的数据 schema 约束。**数据载体形态**承接 ADR-003：git 仓内纯 markdown（人工只可碰 Page 与 reviews.md 裁决态，`state.json` 由 `wiki-rescan` 维护、手不要碰）。本规范为「数据载体规范」，按约定描述 schema 即可；真实 `wiki/` 目录的建立由下游卡（RM-103）执行，本规范不生成真实产物。

## 1. corpus 存储布局（C-010）

```text
wiki/                          # 项目文档 wiki（单 corpus · 接 ../../wiki/ L3 占位坑）
  index.md                     # 导航入口（每页经 wikilink 可达）
  concepts/  entities/  sources/   # 三类提炼页
  _meta/state.json  log.md  reviews.md
wiki-background/<corpus>/       # 背景 wiki（接口占位 · O-001 不实接）
  （同构独立布局 · 各自 index/state/log/reviews/lint · 注册表落点占位 · S-007）
```

| 编号 | 规则 | 级别 | 校验方式 |
|---|---|---|---|
| WD-001 | 每个 corpus = 一个独立 wiki 目录，各自独立 `index.md`/`_meta/state.json`/`log.md`/`reviews.md`/lint；跨 corpus 无外键/级联 | MUST 人工 | 评审 + lint |
| WD-002 | **git 即事实源**（ADR-003）：所有产物入仓 markdown，每批 `--commit-batch` 后一次 git commit（批与 commit 一一对应 · 可 git revert 任意批）| MUST 人工 | git 历史核对 |

## 2. Page schema（提炼页 · `<W>/concepts|entities|sources/*.md`）

### 2.1 frontmatter（受限 YAML · 门禁3 硬要求）

| 字段 | 类型 | 必填 | 约束 |
|---|---|---|---|
| `title` | string | ✅ | 非空 |
| `type` | enum | ✅ | `concept` / `entity` / `source`（小写三选一）|
| `sources` | list[path] | ✅ | 块列表 ≥1 条；**相对仓库根的源文件路径 · 路径必须真实存在**（门禁3 校验）|
| `attribution` | path | 可选 | 源有许可要求时必填 |

> **受限 YAML 解析**：只支持 `key: value` 与块列表（`key:` + 缩进 `- item`）；**不支持嵌套对象/行内列表/多行字符串**；键名小写。

### 2.2 正文约束

| 编号 | 规则 | 级别 | 校验方式 |
|---|---|---|---|
| WD-003 | 提炼**非复制**（400–900 字 · schema §5 摄取模板）；关键结论**注明出处**（两跳溯源第二跳引源文件路径）| MUST 人工 | 评审 + 门禁4 coverage |
| WD-004 | 相关概念 **wikilink 互链**（门禁1 `[[wikilink]]` 可解析无断链 + 门禁2 从 `index.md` 经 wikilink 可达 · 无孤页）| MUST 机械 | wiki-lint 门禁1/2 |
| WD-005 | 与既有页结论**矛盾时禁止静默改写**——登记 ReviewItem（reviews.md `status: open` · 见 §4）| MUST 人工 | 文档 wiki 查询与摄取规范 WK-J1 |

## 3. Manifest schema（`<W>/_meta/state.json` · wiki-rescan 维护 · 手不要碰）

| 字段 | 内容 |
|---|---|
| `source_dirs` | 源目录列表 |
| `exclude` | 按 basename 排除（默认含 `ATTRIBUTION.md`）|
| `extensions` | 源扩展名（缺省 `[".md"]`；`--init --ext` / `--set-ext` 配置）|
| `manifest` | **路径 → 上次摄取时的 SHA256**（rescan 比对判据 · drift 检测核心）|
| `last_commit` | git 候选收窄用（rescan git diff 基点）|
| `current_batch` | 批次 id + 文件 + log 快照（`log_prefix_sha256` · 门禁5 用）|

| 编号 | 规则 | 级别 | 校验方式 |
|---|---|---|---|
| WD-006 | `state.json` **只读（手不要碰）**——仅 `wiki-rescan` 写；manifest SHA256 基线**单调推进**（只在批 committed 时写回 · 一致性提交点）| MUST 人工 | 评审 |
| WD-007 | rescan 以 manifest SHA256 为判据出 changed/new/deleted（git diff 仅收窄候选 · 开销 O(changed) 非全量哈希）；deleted 源经 `--forget` 摘除 | MUST 机械 | wiki-rescan 行为 |

> **AC-d 依据**：rescan 输出的 **changed / new / deleted** 三类清单，判据即 `state.json.manifest`（路径 → SHA256）与当前仓内源文件 SHA256 的逐项比对——新增路径 = new，SHA256 不一致 = changed，manifest 有而仓内缺 = deleted。三态与 state.json schema 可逐字对照。

## 4. log.md schema（`<W>/_meta/log.md` · append-only · 主可观测面）

| 编号 | 规则 | 级别 | 校验方式 |
|---|---|---|---|
| WD-008 | `log.md` **append-only**（门禁5 以 `state.json.current_batch.log_prefix_sha256` 比对 SHA256 前缀 · 改历史 → lint exit 1）| MUST 机械 | wiki-lint 门禁5 |
| WD-009 | 内容 = 摄取批条目（每批一段）+ 裁决条目 `## review:<n> \| <UTC> \| <裁决人>`；本批须有新条目（门禁5）| MUST 机械+人工 | wiki-lint 门禁5 + 评审 |

> log.md 是本模块**主可观测面**（cross-cutting-observability.md §1）：「什么时候摄了哪批、裁决了哪条矛盾」全可追溯，append-only 受门禁机械保证。无 metrics 端点/无 APM（ADR-003 后果段）。

## 5. reviews.md schema（`<W>/_meta/reviews.md` · 留人裁决）

每条字段（门禁6 校验齐全）：

| 字段 | 约束 |
|---|---|
| `type` | `contradiction` / `duplicate` / `missing-page`（M3.1 ReviewKind）|
| `source` | 非空（涉及源）|
| `affected-pages` | 非空（受影响页）|
| `status` | `open` / `resolved`（**条目永留作审计** · lint 对 `open` 放行）|

| 编号 | 规则 | 级别 | 校验方式 |
|---|---|---|---|
| WD-010 | ReviewItem 条目**永久保留**作审计痕迹（禁删）；`status: open → resolved` 流转；**lint 绿 ≠ 无待裁决矛盾**（lint 对 open 放行 · C-005）| MUST 人工 | wiki-lint 门禁6 + reviews.md 留存 |
| WD-011 | 裁决者归属本轮**占位**（O-004）；裁决落实 → 改受影响页 + `status: resolved` + log.md 追 `## review:<n>` | SHOULD（占位 · 操作机制留 O-004）| 评审 |

## 6. extracted/ schema（`<W>/_meta/extracted/` · 本轮 N/A）

- `wiki-extract` 的 PDF/DOCX 抽取稿（工具产物 · 非 wiki 页面 · 可随时重生）；
- **本轮空**（O-007/C-009 · 无非 .md 源）；Page.`sources` 始终指原件路径（即便会话读抽取稿）。

## 7. 数据生命周期对照（承接 data-lifecycle.md）

| 生命周期态 | 数据载体动作 | 锚点 |
|---|---|---|
| 创建（摄取）| 双刀白名单准入 → 建 Page + 互链 + 更 index + append log → lint exit 0 → commit-batch 落 manifest | 文档 wiki 查询与摄取规范 WK-I |
| 更新（drift）| rescan（git diff + SHA256）出 changed → 增量批重摄 | WD-007 |
| 删除（源删）| 清页面引用 → `--forget` 摘除 manifest → lint | WK-I5 |
| 裁决（矛盾）| reviews.md `open → resolved` + log 追 review | WD-010 |
| 备份/回滚 | git 即备份与回滚（git revert 任意批 · 无独立备份系统）| ADR-003 后果段 |

## 8. 例外与豁免

- 本规范为模块专属新增 Rule，与既有 `.harness/rules/` 四件套并列不冲突；任何偏离须在变更目录 `summary.md` 的「例外」区块登记理由与影响面，并经 Reviewer 同意；临时豁免须标注复原计划。
