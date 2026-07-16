---
source: curated
corpus: harness-lessons
title: Harness 工程教训策展经验库 · 索引
---

# Harness 工程经验先验库（harness-lessons）

> **这是什么**：本目录是一个随插件分发的**策展经验库**（curated corpus）。它不是自动调研写入区，而是把若干条跨项目、可泛化的**工程教训**脱敏改写成的先验页面，供任何消费方项目在**设计 / 评审阶段批判性吸收**。
>
> **怎么用**：这些页面是**经验先验，不是硬约束**。每页按「问题模式 + 当时怎么解 + 最终方案 + 适用性判断」四要素组织，末尾都给出「何时适用 / 何时不适用」——请结合你自己项目的语境与约束**判适用性后再采纳**，切勿把它们当成无条件规则盲目套用，也不要只看负面就浅尝辄止。批判性平衡吸收三要点：①完整吸收（能复述问题+解法+方案）②判适用性③采纳/改造/不采纳各留一句理由。
>
> **为什么自带这段说明**：背景 wiki 集合根的体例说明文档不随插件镜像抵达消费方，故本库的体例与来源约定内置于本 index，使本库自足可读。
>
> **来源与脱敏**：页面内核来自某 Harness 体系建设过程中沉淀的跨项目工程记忆，已做脱敏改写——去除了发布戳、内部编号、实例专属实测数与消费方标识，泛化了本仓专属的路径与工具名（Claude Code 平台通用机制名如 CLAUDE.md、SessionStart、git worktree 等予以保留）。因此每页均可脱离原始上下文独立理解。
>
> **旁路定位**：本库是按需查询的经验证据工具，**不进任何阶段的质量门禁判定式**，不夺裁决权、不阻塞主流程。

---

## 经验页面清单

### 子 Agent 与委派成本

- [[subagent-context-inheritance-cost]] —— 子 Agent 强制继承主配置文件的上下文成本，及"缩小被继承体"这一唯一解。
- [[delegation-cost-discipline]] —— 委派成本由"回合数×上下文深度"驱动，一套加厚证据注入 + 分档 + 并发的降本纪律。
- [[auditing-delegation-from-transcripts]] —— 从会话记录（transcript）而非产物文档审计委派是否合规的方法。

### 分发与配置传导

- [[template-instantiation-no-propagation]] —— create-if-missing 模板的改动不惠及存量项目，须另想传导路径。
- [[regenerating-scripts-clobber-manual-edits]] —— 整体重生成下游文件的同步脚本会回退人工改动，是"每次都要查"而非"已根治"。

### git 工作树与治理门

- [[shared-worktree-contention]] —— 多会话共享同一 git 工作树时的分支争用与未提交产物丢失。
- [[governance-gate-vs-verbal-authorization]] —— 机械治理门只认"分支→PR→授权"路径，口头授权≠机械合规路径。
