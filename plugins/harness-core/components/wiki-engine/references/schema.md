# wiki-engine schema 全文 · 页面模板与 wikilink 约定

> SKILL.md 的展开参考。lint 检查编号对应 `bin/wiki-lint` 的六项门禁。

## 1. 目录布局

```
<wiki 根>/
  index.md                 # 导航入口（无 frontmatter 要求；lint 检查 2 的根）
  concepts/                # 概念页：跨源提炼的主题（多数页面在这里）
  entities/                # 实体页：具体的人/库/API/产品等
  sources/                 # 源页：当一个源文件本身值得一页时（逐文件综述）
  _meta/
    state.json             # 由 wiki-rescan 维护，手不要碰
    log.md                 # append-only 日志（摄取批次 + review 裁决）
    reviews.md             # 待办（矛盾/重复/缺页），留人裁决
    extracted/             # wiki-extract 的 PDF/DOCX 文本抽取稿
                           # （工具产物，不算 wiki 页面，可随时重新生成）
```

三类页面的选择：内容围绕"概念"组织优先入 `concepts/`；命名实体入
`entities/`；仅当需要逐文件综述时用 `sources/`。spike 实践：教程类语料
一章一个 concept 页即可。

## 2. 页面模板（lint 检查 3 的硬要求）

```markdown
---
title: <页面标题，非空>
type: concept | entity | source        # 三选一，小写
sources:
  - <相对仓库根的源文件路径>            # 块列表，≥1 条，路径必须真实存在
attribution: <署名文件路径>             # 可选；源有许可要求时必填
---

# <页面标题>

正文：提炼不是复制。每个关键结论后注明出处，例如
（源：spike/adr002/sources/let.md）。相关概念用 wikilink 互链。
```

frontmatter 解析是受限 YAML：只支持 `key: value` 与块列表
`key:` + 缩进 `- item`；不支持嵌套对象、行内列表、多行字符串。
键名小写。`title`/`type`/`sources` 必填，其余可选。

## 3. wikilink 约定（lint 检查 1/2）

- 形式：`[[concepts/promise]]` 或带显示文字 `[[concepts/promise|Promise]]`；
  可带锚点 `[[concepts/promise#错误处理]]`（解析时忽略锚点）。
- 路径**相对 wiki 根**，`.md` 后缀可省略。
- 检查 1：每个 wikilink 必须解析到真实存在的页面文件（断链 = 违规）。
  因此**禁止链接尚不存在的页面**；想标记"该建未建"，登记
  reviews.md（type: missing-page）。
- 检查 2：每个页面必须从 `index.md` 出发经 wikilink 可达（孤页 = 违规）。
  新建页面后立即把它挂进 index 或某个已可达页面。

## 4. _meta 文件格式

### log.md（lint 检查 5）

append-only：历史区一个字节都不许动（begin-batch 时做 SHA256 快照，
lint 校验前缀）。两类条目：

```markdown
## batch:<id> | <UTC ISO 时间> | model:<模型名>
- sources: <本批源文件名，逗号分隔>
- pages: <本批新建/更新页面路径，逗号分隔>
- notes: <一句话：异常、决定、是否登记 review>

## review:<序号> | <UTC ISO 时间> | <裁决人或会话标识>
- item: <对应 reviews.md 条目的一句话指代>
- verdict: <采纳哪边、改了什么>
```

### reviews.md（lint 检查 6）

```markdown
- type: contradiction | duplicate | missing-page   # 三选一
  source: <触发本条的源文件路径>                    # 必填非空
  affected-pages: <受影响页面路径，逗号分隔>         # 必填非空
  status: open | resolved                           # 裁决后改 resolved，条目保留作审计
  note: <一句话说明分歧/重复/缺口>
```

顶层 `- ` 起头的行必须是 `- type: …`；后续键行缩进两格。裁决（review
工作流）只改 `status` 与落实页面修改，不删除条目。

lint 检查 6 强制校验：`type` ∈ 三选一、`source`/`affected-pages` 非空、
**`status` 必填且 ∈ {open, resolved}**——表外值（如 `unresolved`）会让
review 工作流按 `status: open` 检索时漏检（协议 §B 实测踩过，见
`docs/adr002-protocol-b-report.md`）。说明文字一律写 `note:` 键。

### state.json（lint 检查 4/5 的数据源；只读）

`wiki-rescan` 维护：`source_dirs`、`exclude`（按 basename，默认含
ATTRIBUTION.md）、`extensions`（源扩展名，缺省 `[".md"]`；init `--ext` /
既有 wiki `--set-ext` 配置）、`manifest`（路径 → 上次摄取时的 SHA256）、
`last_commit`（git 候选收窄用）、`current_batch`（批次 id、文件、log 快照）。

## 5. 摄取会话提示词模板（spike 验证过的路径）

骨架（按批填充 `<...>`；增量批把第 2 步换成"读源 + 读既有页 → 合并"，
并强调矛盾铁律）：

```
任务：wiki 摄取，批次 <id>。当前目录是仓库根，wiki 根 = <W>。
本批源文件：<清单>
步骤：
1. 逐个完整读取本批源文件。
2. 为每个源文件创建/更新页面 <W>/concepts/<源文件同名>.md，
   frontmatter 严格用模板（schema.md §2）；正文 400–900 字提炼；
   关键结论注明出处；互链只允许指向已存在或本批将创建的页面。
3. 更新 <W>/index.md：保留已有内容，为新页面追加导航行。
4. <W>/_meta/log.md 末尾追加本批条目（只许追加）。
5. 矛盾/重复/缺页 → 按格式登记 <W>/_meta/reviews.md；
   禁止改写既有页面结论，禁止把矛盾说法混入正文。
6. 直接执行（勿加 python3 前缀，否则会被权限白名单拒绝）：
   .harness/components/wiki-engine/bin/wiki-lint --wiki <W>
   非 0 则按 JSON 报告修复重跑，直到 exit 0。
禁止：改源文件；改 _meta/state.json；跑 wiki-rescan --commit-batch。
完成标志：wiki-lint exit 0。最后单独输出一行：LINT-GREEN
```

会话结束后编排方**必须独立重跑 lint**——无头会话自称绿不算数
（spike 实测出现过权限被拒后自称"手动校验通过"的纪律漂移）。

批内含 PDF/DOCX 时：编排方在起会话**之前**跑
`wiki-extract --wiki <W> <files>`，并在模板第 1 步后追加一句：
"非 .md 源读 `<W>/_meta/extracted/<路径 slug>.md` 抽取稿，页面
frontmatter 的 sources 写**原始文件路径**（不是抽取稿路径）。"

## 6. 已知边界

- 受限 YAML 解析器（§2）之外的 frontmatter 写法会被检查 3 判违规——
  这是故意的：格式收窄 = 便宜模型的出错面收窄。
- lint 检查 4 的覆盖目标：有进行中批次时 = 批内文件；否则 = manifest
  全量。源删除后记得 `--forget`，否则检查 4 会一直要求已删除源的页面。
- `git diff` 只用来收窄变更候选，SHA256 才是判据；非 git 环境自动
  全量 SHA256 比对，行为一致只是慢。
- 非 .md 源走 `wiki-extract` 文本抽取：版式/图表丢失、扫描件无 OCR
  （抽空按 5 报错）；PDF 依赖 `pdftotext`（poppler-utils，唯一可选
  外部依赖，缺失退出码 6 诚实报错）。**代码文件刻意不支持**——token
  成本高且"提炼不是复制"纪律难守，建 wiki 应取代码的文档而非代码本身。
