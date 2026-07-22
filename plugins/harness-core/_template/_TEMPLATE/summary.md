# 变更摘要 · {{变更类型}}-{{需求名称}}-{{YYYYMMDD}}

> 本文件是该变更的 **Single Source of Truth**。每阶段完成后**立即覆盖式更新对应区块**（禁止无脑追加导致重复行）。
> 状态受控值：`PENDING` / `IN_PROGRESS` / `PASSED` / `BLOCKED`。
>
> **新建/状态变更后建议自检**：`bash .harness/scripts/list_changes.sh --all`（或 `/list-changes`）—— 验证本变更被 `UserPromptSubmit` hook 正确归类（活跃 / 闭合 / 异常）。归类逻辑见 hook L82–L106；常见误识别原因见基线 §5.6（如"总体状态"含 `**` 修饰或 `CLOSED(...)` 等非精确 enum 时被漏识别）。

## 头部
| 项 | 值 |
|---|---|
| 变更类型 | {{feat / fix / refactor / chore}} |
| 需求名称 | {{英文 slug · 与目录名后段一致 · hook 与脚本读此字段}} |
| 中文描述 | {{一句话中文描述 · 供 /list-changes 与 INDEX.md 展示}} |
| 原始请求 | {{你输入的原话或核心诉求摘要 · 用于回溯"哪段对话发起了本变更"}} |
| 日期 | {{YYYYMMDD}} |
| 当前阶段 | {{1~10}} |
| 总体状态 | {{PENDING / IN_PROGRESS / PASSED / BLOCKED}} |
| —— 以下为 Q8 §5 对接字段（英文字段行 · 走 list_flows.sh 字段通道，上方中文标签行不受影响）—— | |
| flow_type | ten-stage | 全部 10 阶段卡必填 · 与元流程 meta-flow 相对 |
| dir_prefix | {{feat- / fix- / chore-}} | 全部必填 · 注册表见 D-04 §2 |
| source | {{roadmap-driven / ad-hoc}} | 全部必填 · Q8.2 |
| roadmap_card_id | {{RM-xxx · source==roadmap-driven 时必填，否则留空}} |
| reason | {{source==ad-hoc 时必填，否则留空}} |
| bug_class | {{fix 卡必填，否则留空}} |
| parent_change_dir | {{fix 卡可选}} |

## 阶段记录
| 阶段 | 状态 | 评审轮次 | 关键产出（链接） |
|---|---|---|---|
| 1 需求分析 | PENDING | - | request_analysis/spec.md |
| 2 需求评审 | PENDING | 0/3 | request_analysis/review/ |
| 3 编码实现 | PENDING | - | coding/coding_report_v1.md |
| 4 编码评审 | PENDING | 0/2 | coding/review/ |
| 5 单测编写 | PENDING | - | unit_test/ |
| 6 单测评审 | PENDING | 0/2 | unit_test/review/ |
| 7 代码推送 | PENDING | - | PR #<n> · https://github.com/<owner>/<repo>/pull/<n> |
| 8 CI 验证 | PENDING | - | ci_result/ci_result.md |
| 9 部署验证 | PENDING | - | deployment/deployment_report.md |
| 10 用户确认 | PENDING | - | - |

## 指标
| 指标 | 值 |
|---|---|
| CI 用例数 (total_tests) | {{n}} |
| CI 通过数 (passed) | {{n}} |
| AI 代码占比 | {{可选}} |

## 例外与豁免
- {{记录偏离规则的项 + 理由 + 影响面 + 复原计划；无则填"无"}}

## 产出物链接
- 需求：request_analysis/spec.md, tasks.md
- 编码：coding/coding_report_vN.md
- 评审：各 review/ 目录
- CI：ci_result/ci_result.md
- 部署：deployment/deployment_report.md
