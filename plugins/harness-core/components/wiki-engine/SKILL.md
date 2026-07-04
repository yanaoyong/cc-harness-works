---
name: wiki-engine
description: >
  Agent-native wiki engine: build, incrementally refresh, review, and query a
  pure-markdown wiki that lives inside the host repo (no desktop app, no server,
  no database — git is the source of truth). Use when the user wants to
  headlessly generate a wiki from source documents, ingest document changes
  incrementally, adjudicate contradiction/duplicate reviews, or answer questions
  grounded in the wiki with two-hop citations. For controlling the
  nashsu/llm_wiki desktop app over its local HTTP API, use the llm-wiki skill
  instead. 无头自建 wiki：全量/增量摄取源文档为互链 markdown wiki，支持留人
  裁决与可溯源查询；操控 nashsu 桌面应用请用 llm-wiki。
---

# wiki-engine

**架构事实（ADR-002）**：引擎 = coding agent 本身（Karpathy 模式）。wiki 是
宿主仓库内的纯 markdown，git 是事实源与回滚机制。无数据库、无常驻进程、
无 GUI。质量不靠模型自觉，靠 `bin/wiki-lint` 六项确定性硬门禁兜底；
便宜模型（DeepSeek 档）只做批量摄取，裁决留给强模型会话。

> EN: The agent is the engine. The wiki is plain markdown in the host repo;
> git provides truth and rollback. Quality is enforced by `wiki-lint`'s six
> deterministic gates, not by model goodwill. Cheap models (DeepSeek tier) do
> bulk ingestion only; adjudication stays in a strong-model session.

**与 `llm-wiki` 的分工**：本 skill 面向"纯 headless 自建 wiki"；`llm-wiki`
是 nashsu 桌面应用的 HTTP 遥控器，面向"已有该桌面应用"的用户。两者互不依赖。

## 诚实边界

- 查询是**词法检索**（index 导航 + ripgrep + 互链），无向量；库大后再升级。
- 摄取质量依赖模型 + lint 门禁，没有上游打磨过的 dedup 引擎；矛盾/重复
  一律进 `reviews.md` 留人裁决，**禁止静默合并**。
- 非 .md 源只支持 **PDF/DOCX 的文本抽取**（`wiki-extract`）：版式/图表/
  扫描件 OCR 不在能力内；PDF 抽取依赖 `pdftotext`（唯一的可选外部依赖，
  缺失时退出码 6 诚实报错）。代码文件**刻意不支持**。

## 目录与 schema（全文见 `references/schema.md`）

```
<wiki 根>/
  index.md                 # 导航入口；每页必须从这里经 wikilink 可达
  concepts/  entities/  sources/   # 三类页面
  _meta/state.json         # 摄取基线（manifest SHA256 + last_commit + 当前批次）
  _meta/log.md             # append-only 摄取/裁决日志
  _meta/reviews.md         # 矛盾/重复/缺页待办（留人裁决）
```

## 工具（在仓库根直接执行脚本；stdout 纯 JSON，诊断走 stderr）

| 命令 | 作用 |
|---|---|
| `.harness/components/wiki-engine/bin/wiki-rescan --wiki <W> --init --source-dir <D>...` | 脚手架 wiki 目录 + state 基线 |
| `.harness/components/wiki-engine/bin/wiki-rescan --wiki <W> [--all]` | 变更清单（git diff 收窄候选，SHA256 为判据） |
| `.harness/components/wiki-engine/bin/wiki-rescan --wiki <W> --begin-batch <id> --files <f>...` | 登记批次（含 log append-only 快照） |
| `.harness/components/wiki-engine/bin/wiki-rescan --wiki <W> --commit-batch` | 批次过门禁后落 manifest |
| `.harness/components/wiki-engine/bin/wiki-rescan --wiki <W> --forget --files <f>...` | 源文件删除后从 manifest 摘除 |
| `.harness/components/wiki-engine/bin/wiki-rescan --wiki <W> --set-ext .md .pdf .docx` | 替换源扩展名列表（init 时用 `--ext`；默认只收 `.md`） |
| `.harness/components/wiki-engine/bin/wiki-extract --wiki <W> <f.pdf> <f.docx>...` | 非 .md 源的确定性文本抽取 → `<W>/_meta/extracted/`（摄取会话读抽取稿，页面 sources 仍指原件） |
| `.harness/components/wiki-engine/bin/wiki-lint --wiki <W>` | 六项硬门禁；exit 0 才算过 |
| `.harness/components/wiki-engine/bin/wiki-ingest-cheap "<prompt>" [claude 额外参数]` | DeepSeek 无头摄取会话（需 `DEEPSEEK_API_KEY`） |

**调用纪律**：权限白名单只放行**直接执行脚本路径**（脚本有执行位），
不要加 `python3` 前缀。无头会话的自述不可信——每批结束后必须由编排方
（你或外层会话）独立运行 `wiki-lint`，以其退出码为权威判据。

## 五条工作流

### 1 · init（一次性）

1. 选定 wiki 根目录与源目录，运行
   `wiki-rescan --wiki <W> --init --source-dir <D>`；
2. 脚手架产物：三类页面目录 + `index.md` + `_meta/`（state 基线 =
   空 manifest，首次 rescan 会把全部源列为 new）；
3. 把脚手架提交进 git（基线可回滚）。

### 2 · full build（首次全量）

1. `wiki-rescan --wiki <W> --all` 拿全部源文件清单；
2. 切批，**每批 ≤5 个源文件**；对每批执行同一批循环：
   a. `wiki-rescan --begin-batch <id> --files <本批文件>`；批内含
      PDF/DOCX 时编排方先跑 `wiki-extract` 生成抽取稿；
   b. 起摄取会话（DeepSeek 档走 `wiki-ingest-cheap`，提示词模板见
      `references/schema.md` §5）：逐个读源（非 .md 源读
      `_meta/extracted/` 抽取稿，sources 仍写原件路径）→ 按页面模板
      建页 + 互链 → 更新 index → 追加 log 条目；
   c. 编排方独立跑 `wiki-lint`，**全绿才** `wiki-rescan --commit-batch`，
      并 git commit 本批；不过门禁则把 lint JSON 报告回喂会话修复，
      仍不过按"约束 → 批量 → 模型档"顺序调参；
3. 全部批次完成后整体跑一次 `wiki-lint` 收尾。

### 3 · incremental（增量）

1. `wiki-rescan --wiki <W>` 拿 changed / new / deleted 三类清单；
2. changed+new 走与全量相同的批循环，差别在合并纪律：**与任何既有页面
   结论矛盾、内容重复、应建未建 → 写 `reviews.md` 留人裁决，禁止静默
   改写既有结论、禁止把矛盾说法混入正文**；
3. deleted：删除/收编引用它的页面段落后，`wiki-rescan --forget --files <f>`
   从 manifest 摘除，再跑 lint（检查 3 会揪出残留的死源引用）。

### 4 · review（裁决，强模型会话，不走 wiki-ingest-cheap）

1. 逐条读 `_meta/reviews.md` 中 `status: open` 的条目；
2. 对照源文件与受影响页面裁决：采纳哪边、如何改写；
3. 落实修改 → 该条目 `status:` 改为 `resolved`（条目本身保留，作审计
   痕迹）→ 在 `log.md` 追加 `## review:<n> | <UTC> | <裁决人>` 条目；
4. 跑 `wiki-lint` 全绿收尾。量小、错了代价高——这一步永远用强模型。

### 5 · query（词法检索，两跳可溯源）

1. 读 `index.md` 定位候选页面；
2. `rg -l "<关键词>" <wiki 根>` 补充候选（中文关键词注意分词变体）；
3. 顺 wikilink 读页，组织回答；
4. **回答必须引用页面路径；页面正文必须引用源文件路径**——两跳链路
   断了就如实说"wiki 没有覆盖"。

## 退出码

| 脚本 | 退出码 |
|---|---|
| `wiki-rescan` | 0 成功 / 2 参数错误 / 5 内部错误 |
| `wiki-lint` | 0 全绿 / 1 有违规（详见 stdout JSON）/ 2 参数错误 / 5 内部错误 |
| `wiki-extract` | 0 成功 / 2 参数或扩展名不支持 / 5 抽取失败 / 6 能力缺失（pdftotext 不可用） |
| `wiki-ingest-cheap` | 0 成功 / 2 参数或环境缺失 / 其余透传 claude 退出码 |

与 `llm-wiki` 同一纪律：0 成功、2 参数、5 内部错、6 能力缺失；1 是
lint 专用的"门禁未过"信号（llm-wiki 无此语义）。
