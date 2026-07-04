---
name: codegraph
description: >-
  用 CodeGraph 查询本仓库的代码结构，替代 grep / 逐个读文件。**首选 `cg explore`**——
  几乎任何「查关系 + 读源码」问题、改动前先调它一次，一次拿 verbatim 源码 + 爆炸半径
  (Blast radius) + 调用路径 + already-Read 路由（explore 里出现过的文件不要再 Read）。
  读单个符号/单个文件用 `cg node`——**用它替代 Read（INSTEAD of Read）**。其余命令为精确
  补充：谁调用某函数 (callers)、某函数调用了谁 (callees)、改动的影响面 (impact)、改动影响
  哪些测试 (affected)、符号查找/消歧 (query)、项目结构 (files)。凡是涉及符号之间关系或读
  源码的问题优先用它。
  Query this repo's code structure via CodeGraph instead of grepping or reading many
  files. **Prefer `cg explore`** for almost any "understand relationships + read source"
  question and before any change: one call returns verbatim source + blast radius + call
  flow + already-Read routing (do NOT Read a file explore already showed). Use `cg node`
  to read a single symbol/file — INSTEAD of Read. The rest are precise supplements: who
  calls X (callers), what X calls (callees), blast radius (impact), affected tests
  (affected), symbol lookup/disambiguation (query), project structure (files).
---

# CodeGraph —— 本仓库的代码结构后端

CodeGraph 在 `.codegraph/` 里维护本仓库的符号图（函数/类 + 调用/导入等关系）。
通过 `cg` 帮手查询它，能用一次工具调用回答结构性问题，而不必反复 grep、读文件。

**帮手 `cg`**：`plugins/harness-core/components/codegraph/bin/cg`（本仓内为 repo-相对路径 · 在仓库根目录运行；经 `cg install-skill` 安装到其他仓库时此处会被注入本机绝对路径）。
在仓库根目录运行它；它负责选运行时、在当前仓库内执行、并把 JSON 打到标准输出。
下文示例里的 `cg` 均指上面这个路径（嫌长可 `alias cg='plugins/harness-core/components/codegraph/bin/cg'`）。

## 何时用 / 何时不用（量化基准实测，见仓库 docs/poc/codegraph-vs-grep-benchmark.md）

- **首选 `explore`/`node`**——绝大多数「关系 + 读源码」问题一条 explore 搞定：
  - 端到端理解流程 / 改动前评估影响面：`cg explore <phrase>` 一次拿 verbatim 源码 +
    调用路径 + 爆炸半径 + already-Read 路由（调完没理由再 Read）。
  - 读单个符号全文 / 读单个文件：`cg node <symbol>` 或 `cg node <file>` —— **用它替代
    Read**（INSTEAD of Read）；file 模式带 `<n>\t<line>` 行号 + 文件依赖提示。
  - callers/callees/impact/query/files 仍在（见下），但作为 explore 之外的**精确补充**。
- **该用**——问的是「关系」，即答案是**符号**而非文本位置：
  - 谁调用了 X / 改 X 波及什么：grep 给的是调用点，要归因到调用者符号还得逐个读文件
    （重名符号 p90 要读 79 个文件）；`cg callers` 一次给出带 `filePath:line` 的符号列表。
  - 影响面/传递问题（尤其被广泛复用的枢纽符号）：grep 要按层 re-grep，实测 ~1/4 的符号
    要 ≥10 次调用；`cg impact` 恒 1 次。
  - 识别重名：`cg query <name>` 一次列出全部同名定义（真实仓库 ~2/3 可调用符号撞名）。
- **别用 CodeGraph、直接 grep**——
  - 找**字符串字面量 / 错误消息 / 配置键 / 注释**：CodeGraph 的搜索只索引符号元数据，
    不索引文件正文，这类查询召回率为 0。
  - 唯一名、只要知道**出现位置**：一次 grep 即可（且单次延迟约为 cg 的 1/40）。
  - 代码刚改过、索引未 `cg sync`：grep 永远新鲜。
- **细读实现时**：用 `cg node <symbol|file>` 读源码（INSTEAD of Read），见上「首选」。

## 先检查索引

```
cg doctor          # 显示运行时 + 是否已建索引
cg init            # 一次性：建索引（仅当 doctor 显示 NOT initialized 时）
cg sync            # 改完代码后、信任查询结果前先同步
```

## 命令

| 问题 | 命令 | 主/辅 | 从输出里读什么 |
|---|---|---|---|
| 理解流程 / 改动前评估 | `cg explore <phrase>` | **PRIMARY** | verbatim 源码 + 调用路径(Flow) + 爆炸半径(Blast radius) + already-Read 路由（**可读文本非 JSON · explore 里的文件不要再 Read**）|
| 读符号 / 读文件（替代 Read）| `cg node <symbol\|file>` | **SECONDARY（INSTEAD of Read）** | 符号模式：完整体 + 调用轨迹 + 歧义名返回每个重载；file 模式：`<n>\t<line>` 行号源码 + 文件依赖提示（**可读文本非 JSON**）|
| 查符号（消歧入口）| `cg query <name>` | 精确补充 | `[{node:{name,kind,filePath,startLine,signature}, score}]`，score 高者在前（**精度纪律前置消歧 · 先 explore 不够再用它定位歧义**）|
| 谁调用 X | `cg callers <name>` | 精确补充 | `{callers:[...]}`（**改动前评估优先 `cg explore`/`cg impact`**）|
| X 调用谁 | `cg callees <name>` | 精确补充 | `{callees:[...]}`（**端到端理解优先 `cg explore`**）|
| 改 X 的影响面 | `cg impact <name>` | 精确补充 | `{depth,affected:[...]}` |
| 改动影响的测试 | `cg affected <file...>` | 精确补充 | 受影响的测试文件 |
| 项目结构 | `cg files` | 精确补充 | `[{path,language,nodeCount,size}]` |
| 索引健康 | `cg status` | 维护 | `{nodeCount,edgeCount,languages,pendingChanges}` |

## ⚠️ 精度纪律（信任结果前必读）

CodeGraph 底层的边是准的，但上面这些命令是**按符号名寻址**的，所以遇到常见名/重载
时会过度上报。务必遵守：

1. **callers/callees/impact 会合并所有同名符号。** `cg` 已内置保护：当某个名字有 >1
   个定义时，它会向 **stderr** 打印一条 `cg: ⚠ N symbols named "<name>" …` 的警告——
   **看到这条警告就说明结果是并集、可能有假阳性**。此时先跑 `cg query <name>` 看清各
   定义的 `filePath:startLine`，再只采信 caller 列表中 `filePath` 匹配你目标定义的那些
   （通常是同模块/同目录），对其余结果保持怀疑。没有该警告则名字唯一，结果可放心用。
2. **搜索是词法的，不是语义的。** 用标识符片段查（`getUser`、`Transport`），别用整句
   自然语言。查不到就换前缀或子串再试。
3. **callers/impact 也会跟随 `imports`/`references` 边**——结果是「依赖方」而非严格的
   「调用方」。只 import 了 X 的文件也可能出现在列表里。
4. **索引过期 = 答案错误。** 若 `cg status` 的 `pendingChanges` 非零，先 `cg sync`。

## 首选 `explore`（几乎任何关系/改动前先调它）

`cg explore <自然语言或符号片段>` 一次就给出相关符号的 **verbatim 源码 + 调用路径
（Flow）+ 爆炸半径（Blast radius）+ already-Read 路由**——源码块是「逐字、与磁盘当前
内容一致、等同于你已经用 Read 读过」的，**explore 里出现过的文件不要再 Read**。
端到端理解一条流程、改动前评估影响面，先 `cg explore`，别手工串 query→callees→impact。

cg explore <entry-point or feature phrase>   # 一次拿全：源码 + 调用路径 + 爆炸半径

读单个符号/单个文件时用 `cg node`（见上「读源码」），**INSTEAD of Read**。

## 失败软化（退出码非阻塞 · 失败做成「下一步引导」而非「工具坏了」）

`cg` 的非 0 退出码都是**非阻塞**的（CGCLI-006）——一两次失败不代表该整段会话弃用
codegraph。按退出码走下一步，别读成「工具坏了」：

- **退 11（NOT_INITIALIZED · 无索引）** → 先 `cg init` 建一次索引，再重跑（一次性 · CG-S0）。
- **退 10（RUNTIME_MISSING · 无运行时）** → 静默降级：本次用 `grep`/`rg` 找出处即可，
  不阻塞主流程（运行时由用 harness 的人按需装 · 见「先检查索引」）。
- **退 13（CG_CLI_ERROR · 查询失败）** → 回退 `grep`/`rg` 找全部出处，并看 stderr 的引擎报错。

不做 MCP 的「空 tools-list 握手秒答 / 冷启动 proxy」——那是引擎/MCP 层机制，不归这里的
CLI adapter 造（O-003）。
