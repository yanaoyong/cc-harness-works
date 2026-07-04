# acceptance-backfill 使用手册

面向直接调用两个 CLI（或经 `/backfill` 剧本编排调用）的操作者。组件定位与分发路径决策见 [README.md](README.md)；锚点/chains/布局/降级约定的权威定义见 `plugins/harness-core/rules/验收回填与证据捕获规范.md`。

两脚本共同契约：仓库根一律 `git rev-parse --show-toplevel` 推导（路径零硬编码）；**stdout 仅一行结构化 JSON 摘要，诊断一律 stderr**；写入面仅 `results/<CASE-ID>-result.md` 与 `results/.evidence/**`，绝不写 `cases/`。

## 1. `acceptance-run.sh` — pre/post 执行器

```sh
acceptance-run.sh <pre|post> <套件根> <CASE-ID> [--dry-run]
```

| 参数/选项 | 说明 |
|---|---|
| `pre\|post` | 提取并执行 case 回填模板【运行前】/【运行后】节的首个 ```bash 块 |
| `<套件根>` | `.harness/acceptance/` 下套件目录；相对仓库根或绝对路径均可 |
| `<CASE-ID>` | 如 `RP-09` / `FS-05`（按 `cases/<ID>.md` 或 `cases/<ID>-*.md` 定位） |
| `--dry-run` | 只定位/提取不执行、零写入（守护测试全集可解析断言用） |

行为要点：

- **标题锚归一化容差**：去空白（含全角）与全/半角中点、【】括号后按 `运行前|运行后` 前缀识别 ≥2 个 `#` 的标题（兼容存量变体；权威规则 rule §1.2）；
- **占位豁免**：节可定位但无 ```bash 块（如 FS-06~14/17/18 占位符）→ exit 0 + 写 `.evidence/<CASE-ID>/<mode>-skipped.note` 显式留痕，不臆造命令；
- **留档**：块 stdout/stderr/退出码 tee 到 `results/.evidence/<CASE-ID>/pre-<时间戳>.log` / `post-<时间戳>.log`；
- **env 状态传递**：pre 成功后以执行前后 env 差分写 `.evidence/<CASE-ID>/env`，post 自动 source（fixture mktemp 路径等实际值，非字面量重求值）。

## 2. `acceptance-capture.sh` — transcript 证据捕获器（含链式切片）

```sh
acceptance-capture.sh <套件根> <CASE-ID> [--session <jsonl路径>] [--chain <链ID>]
                      [--no-thinking] [--dry-run]
```

| 参数/选项 | 说明 |
|---|---|
| `<套件根>` | 同上；相对仓库根或绝对路径均可 |
| `<CASE-ID>` | 案例 ID（`cases/<CASE-ID>*.md` 须在场） |
| `--session <jsonl路径>` | 显式指定被测会话 JSONL，跳过自动定位（定位失败/多候选歧义时的手工出口） |
| `--chain <链ID>` | 链式切片模式：读 `<套件根>/chains.md` 与进度文件，链首钉 UUID、成员按 [进入锚, 出口锚) 切片 |
| `--no-thinking` | 渲染时完全去除 thinking（默认渲染为 "[thinking ×N 已省略]" 行） |
| `--dry-run` | 只做定位/解析/切片校验，不落任何文件 |

行为要点：会话定位按 case 【运行前】块 `cd` 目标换算 `~/.claude/projects/<cwd 转义>/` 项目目录，独立案例按启动 prompt 原文匹配；渲染过保守脱敏（`*_API_KEY`/`*_TOKEN`/`password=`/`secret=` 等值打码）；三源合并（pre 日志/transcript 渲染/post 日志）产出 result 草稿，骨架服从套件 `results/README.md` 既有契约，判定字段留空待用户；既有非空 result 先备份 `.evidence/<CASE-ID>/result-backup-<时间戳>.md` 再覆写。"跑过头"回切 = 逐成员各调一次本脚本（链首 UUID 已钉进度文件，后续成员零重匹配）。依赖 `python3`（缺失 → exit 5 明确提示）。

## 3. 退出码（两脚本共用枚举）

| 退出码 | 语义 |
|---|---|
| 0 | 成功（含占位豁免留痕） |
| 1 | 断言性失败（被执行块内命令非零退出 / 锚缺失） |
| 2 | 参数错误 |
| 3 | （capture 专用）会话定位失败 |
| 4 | （capture 专用）transcript 格式版本不识别 |
| 5 | 内部错误（含依赖缺失） |

## 4. 已知坑（五条）

1. **transcript 为 Claude Code 内部格式，无兼容承诺**：`~/.claude/projects/**.jsonl` 字段随版本演进可能变化。capture 做防御性解析——不认识的格式版本 → **exit 4 降级**：原始 jsonl 已归档 `.evidence/<CASE-ID>/` + result【运行中】节留空写"待人工摘录"提示，**永不静默丢证据、不臆造内容**；守护测试只承诺对 fixture 格式的行为。
2. **多候选会话需人工挑选**：同一转义项目目录下多条 JSONL 可能都含相似 prompt（重跑场景）。匹配取"prompt 原文完全匹配 + 最新 mtime"优先并向 stderr 列全部候选；歧义时 exit 3，用 `--session <jsonl路径>` 手工指定，脚本不静默选错。
3. **fixture 会话的 transcript 不落本仓项目目录**：在 fixture 目录（如 mktemp 的 /tmp 工作目录）内开的会话，其 JSONL 落 **/tmp 对应的转义项目目录**（如 `~/.claude/projects/-tmp-xxx/`）而非本仓目录。capture 从 case 【运行前】块 `cd` 目标解析 cwd 换算转义路径；解析不出 `cd` 目标时报错提示手工指定。
4. **redact 短值有漏杀面**：打码模式针对"键名含 KEY/TOKEN/SECRET/PASSWORD 且值 ≥16 字符"与 Bearer 头；**短于 16 字符的密钥值或非常规键名不会被打码**。含敏感环境的案例回填定稿前请人工过目一遍摘录。
5. **acceptance-run 执行的是案例自带 bash 块**：pre/post 块内容来自 case 文件（受审入库产物），仅应在用户显式发起的回填流程中运行；拿不准时先 `--dry-run` 查看将执行的块再实跑。
