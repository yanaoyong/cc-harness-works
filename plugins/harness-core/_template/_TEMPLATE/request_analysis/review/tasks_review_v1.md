# 计划评审报告 · tasks_review_v1

> 阶段2 产出（计划评审）。由 `expert-reviewer` 生成。版本递增（v1→v2…），旧版永不删。
> 与 `spec_review_vN.md` 配套；计划评审须同时产出两份报告。

## 评审对象
- tasks.md（版本：{{...}}）
- 对照依据：同目录上级 `spec.md`（范围与验收标准是否一致）

## 意见列表
> 每条格式 = 问题描述 + 修改建议 + 优先级（MUST FIX / LOW / INFO）。

| # | 问题描述 | 修改建议 | 优先级 |
|---|---|---|---|
| 1 | {{子任务是否缺目标/范围/输入输出/验收标准/依赖}} | {{...}} | {{MUST FIX / LOW / INFO}} |
| 2 | {{任务拆分粒度是否可验证、是否过大}} | {{...}} | {{MUST FIX / LOW / INFO}} |

## 结论
- {{APPROVED / REVISION REQUIRED}}
- MUST FIX 数：{{n}}
- 本轮轮次：{{k}}/3（与 spec_review 同轮；超出升级人工）
