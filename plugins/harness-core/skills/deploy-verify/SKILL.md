---
name: deploy-verify
trigger: 阶段9 部署验证
inputs: 阶段8 CI 通过、HITL-4 确认的部署参数
outputs: deployment/deployment_report.md
version: 1.1.0
updated: 2026-06-02
stack: vendor-neutral（具体栈见 HARNESS_CONFIG.yaml）
spec: docs/stage-01-Harness体系建设/02-体系设计/06-Skills技能体系规范.md
---

# Skill · 部署验证（deploy-verify）

> 默认对**服务启动 + 健康检查端点探活**做验证（具体启动命令与探活端点见栈特定层 / `HARNESS_CONFIG.yaml` / 业务仓覆盖）；业务仓可覆盖下方命令。**部署参数禁止推测**。

## 1. 目的
在 CI 通过后，于指定环境完成部署并验证关键路径，确认可交付。

## 2. 触发条件
进入 **阶段9**（阶段8 CI 通过，且 **HITL-4 部署参数已人工确认**）时加载。

## 3. 输入
- HITL-4 确认的部署参数表（环境、版本、配置等）；
- 阶段1 `spec.md` 中的验收标准（选取可自动化项）；
- 部署/服务启动方式（具体启动命令见栈特定层 / `HARNESS_CONFIG.yaml` / 业务仓覆盖）：`<服务启动命令> --host 0.0.0.0 --port {{PORT}}`；
- 健康检查（端点按栈特定层实现）：`curl -sf http://{{HOST}}:{{PORT}}/health`。

## 4. 步骤（SOP）
1. **禁止推测**任何部署参数；缺参则暂停并请求 HITL-4。
2. 按确认参数执行部署（容器/K8s/裸机脚本由 HITL-4 指定）。
3. 执行验证项（**至少一项探活**）：

   ```bash
   # 健康检查（健康检查端点须由栈特定层实现：GET /health → 200）
   curl -sf "http://${HOST}:${PORT}/health"

   # 冒烟：核心 API（示例，以 spec.md 为准）
   curl -sf -X POST "http://${HOST}:${PORT}/v1/prices/batch" \
     -H "Content-Type: application/json" \
     -d '{"sku_ids":["SKU001"]}'
   ```

4. 可选：日志无 ERROR、Playwright MCP E2E（见 `docs/stage-01-Harness体系建设/03-质量与改进/08-质量门禁与反馈回路规范.md` L4）。
5. 填写 `deployment_report.md`（参数表须标注确认人）。

## 5. 产出物
- `../../changes/<变更目录>/deployment/deployment_report.md`

## 6. 完成判据
- 部署参数表经 HITL-4 确认且与执行一致；
- 验证项表全部通过或已记录例外（须在 `summary.md` 登记）；
- 报告结论为「通过」方可进入阶段10。

## 7. 引用
- 模板：`../../_template/_TEMPLATE/deployment/deployment_report.md`
- 规则：`../../rules/开发流程规范.md`（DF-004 HITL）
- 编排中枢 HITL-4：`../../agents/application-owner.md`
- 门禁：`docs/stage-01-Harness体系建设/03-质量与改进/08-质量门禁与反馈回路规范.md`（L4 运行反馈，可选 Playwright MCP）
