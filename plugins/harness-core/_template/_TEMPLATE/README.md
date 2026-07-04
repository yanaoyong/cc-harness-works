# _TEMPLATE/ —— 变更目录模板

> 每个需求复制本目录为 `{变更类型}-{需求名称}-{YYYYMMDD}/`，按 10 阶段推进时逐步填充。
> 规范：`docs/stage-01-Harness体系建设/03-质量与改进/09-变更管理与持久化记忆规范.md`。

## 使用方式
1. 复制 `_TEMPLATE/` → `feat-示例需求-20260531/`（变更类型取值：`feat`/`fix`/`refactor`/`chore`）。
2. 各阶段产出写入对应子目录；评审/报告类文件**版本递增**（`_v1`→`_v2`…），**旧版永不删**。
3. `summary.md` 为该变更唯一事实来源，**每阶段完成立即覆盖式更新对应区块**（禁止无脑追加）。

## 结构
```
{变更类型}-{需求名称}-{YYYYMMDD}/
├── summary.md
├── project_analysis/  project_analysis_report.md / module_map.md（按需，见 project-analysis Skill）
├── request_analysis/  spec.md / tasks.md / review/
├── coding/            coding_report_vN.md / review/code_review_vN.md
├── unit_test/         unit_test_report_vN.md / review/
├── ci_result/         ci_result.md
└── deployment/        deployment_report.md
```
