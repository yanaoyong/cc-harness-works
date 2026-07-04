# skills/ —— 技能体系（② 怎么做 / SOP）

> 可复用的标准化工作流程，按阶段触发加载（L2）。
> 规范：`docs/stage-01-Harness体系建设/02-体系设计/06-Skills技能体系规范.md`。
> 状态：**阶段流程 Skill 7 个已落地（Python 1.1，2026-06-02 阶段 C）**；`project-analysis` 已落地；`aone-ci-generate` 待补。

## 技能索引（对接 docs/stage-01-Harness体系建设/02-体系设计/07-十阶段流程详细规范.md 阶段 / docs/stage-01-Harness体系建设/02-体系设计/04-编排中枢-ApplicationOwner定义规范.md 模块二）

| Skill 目录 | 触发阶段 | 职责 | 落地批次 | 状态 |
|---|---|---|---|---|
| `request-analysis/` | 阶段1 需求分析 | 产出 spec.md / tasks.md | 核心 | ✅ |
| `expert-reviewer/` | 阶段2/4/6 评审 | 计划评审 / 执行评审 | 核心 | ✅ |
| `coding-skill/` | 阶段3 编码实现 | 分层编码（含 8 份分层 Spec 索引） | 核心 | ✅ |
| `unit-test-write/` | 阶段5 单测编写 | 改动驱动测试 | 核心 | ✅ |
| `code-review/` | 阶段4 | 代码检查清单（配合 reviewer） | 后补 | ✅ 最小占位 |
| `unit-test-ci/` | 阶段8 CI 验证 | 流水线验证 + 三条件门禁 | 后补 | ✅ 最小占位 |
| `deploy-verify/` | 阶段9 部署验证 | 部署后验证 | 后补 | ✅ 最小占位 |
| `project-analysis/` | 按需 | 项目结构分析 | 按需 | ✅ |
| `aone-ci-generate/` | 按需 | CI 配置生成 | 按需 | ⏳ 待补 |

> 每个 Skill 一个目录，含 `SKILL.md`（结构见 `docs/stage-01-Harness体系建设/02-体系设计/06-Skills技能体系规范.md §3`）。Claude Code 经 `.claude/skills/` 桥接指针加载（`docs/stage-01-Harness体系建设/04-运行手册/12-运行时集成-ClaudeCode桥接规范.md`），权威正文在 `.harness/skills/`。
