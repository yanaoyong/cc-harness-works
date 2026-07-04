---
name: fe-unit-test-write
description: React+Vite 栈单测编写操作 how——vitest + React Testing Library、改动驱动测试覆盖 FE 分层、真实并发用例 FE 写法、测试根 *.test.tsx（FE-5）；引用 §4 FE-5 与绑定声明不复制（C-3）。
trigger_phase: 5
trigger: 阶段5 单元测试编写（React+Vite 栈 · 与核心 unit-test-write 配合，承载 vitest/RTL how）
inputs: 阶段4 通过的 FE 代码与改动接口清单、绑定声明 react-vite-binding.md、项目编码规范.md §4 FE-5
outputs: vitest 测试模块、单测报告
version: 1.0.1
updated: 2026-07-02
spec: docs/stage-01-Harness体系建设/02-体系设计/06-Skills技能体系规范.md
stack: react-vite
---

# Skill · React+Vite 单元测试编写（fe-unit-test-write）

> **栈特定层 · FE 测试 how**。本 skill 承载 RM-127 从核心 `unit-test-write` 去串掉的 **vitest + React Testing Library** 编写 SOP；与栈无关骨架 `plugins/harness-core/skills/unit-test-write/` **配合**（骨架管「改动驱动 / 覆盖映射 / 真实并发纪律」的栈无关原则，本 skill 管「React+Vite 栈下怎么写」）。
> **引用不复制（C-3 单源）**：测试根/命名约定权威在 `项目编码规范.md §4 FE-5`，测试命令实值在绑定声明 `react-vite-binding.md` `testCommand()`；本 skill 不重定义 FE-5 约束。

## 1. 目的

为本次 React+Vite 改动编写**有业务价值**的 vitest 用例，保障阶段8 门禁 `total_tests > 0 && passed == total` 且可回归。

## 2. 触发条件

进入 **阶段5**（阶段4 编码评审通过且 HITL-3 通过 · 可与阶段4 并行）且 `stack` 为 React+Vite 时，与核心 `plugins/harness-core/skills/unit-test-write/` 一并加载。

## 3. 输入

- 阶段4 通过的 FE 代码与改动组件/hooks/服务清单；
- 绑定声明 `react-vite-binding.md`（实体未迁入 plugin · 待补 · 受控前向引用，见 fe-coding-skill §3；`testCommand()` = `vitest run`）；
- 测试根/命名约定：`plugins/harness-core/rules/项目编码规范.md §4 FE-5`（测试文件 `*.test.tsx`/`*.test.ts`）；
- FE 分层 Spec：`.harness/skills/fe-coding-skill/specs/`（消费方项目本地镜像路径 —— 指向项目安装后由 hook 落盘的本地副本；RM-132/133 产物 · 覆盖依据）。

## 4. 步骤（SOP）

1. **改动驱动**：改了哪个 UI 组件/容器/hooks/服务就测哪个，而非只测无关模块（覆盖映射：组件/函数 → 测试文件/用例名）。

2. **前置配置**（UT-1/UT-2 · 步骤3 用法生效的前提，缺失则组件测试在 CI 直接崩溃）：
   - **测试环境 jsdom（UT-1）**：`vitest.config.ts` 须设 `test.environment: 'jsdom'`（或 happy-dom）。缺失症状：组件测试无 DOM 环境，CI 报 `document is not defined`，阶段8 门禁 `total_tests > 0` 无法满足。
   - **jest-dom 扩展断言（UT-2）**：同一配置的 `setupFiles: ['@testing-library/jest-dom/vitest']` 引入 `@testing-library/jest-dom` 扩展断言（如 `toBeInTheDocument()`）。缺失症状：`toBeInTheDocument is not a function`。
   - 一行可复制配置示例（置于 `vitest.config.ts` 的 `defineConfig({...})` 内）：

     ```ts
     test: { environment: 'jsdom', setupFiles: ['@testing-library/jest-dom/vitest'] }
     ```

3. **vitest + React Testing Library 基础用法**（官方文档：https://vitest.dev / https://testing-library.com/react）：
   - **组件测试**：用 `render(<Component />)` 渲染组件，`screen.getByText()`/`getByRole()` 查询元素，`userEvent.click()` 模拟用户交互，`expect(element).toBeInTheDocument()` 断言。
   - **Hooks 测试**：用 `renderHook(() => useXxx())` 测试自定义 hook，`result.current` 访问返回值，`waitFor()` 等待异步更新。
   - **Services 层测试**：用 `vi.mock()` 拦截外部 HTTP 调用（如 `fetch`），断言 services 函数对 mock 响应的处理逻辑。
   - **异步测试**：用 `await waitFor(() => expect(...))` 等待异步状态更新；用 `async/await` 处理 Promise 返回。

4. **覆盖 FE 分层**（按 ES-FE-1~5 与 RM-132/133 FE Spec）：
   - **components（UI 层）**：测试纯展示逻辑（props → 渲染输出），无副作用、无 API 调用。
   - **containers（容器层）**：测试编排逻辑（组件组合 + 状态管理 + 调用 hooks/services），mock 下游依赖。
   - **hooks（逻辑层）**：测试状态/副作用封装（`useState`/`useEffect` 逻辑），用 `renderHook` 独立测试。
   - **services（服务层）**：测试对后端 API 的调用封装（超时/降级/错误处理），mock `fetch` 验证请求参数与响应处理。

5. **测试文件落点**（FE-5）：测试文件就近放置（`*.test.tsx`/`*.test.ts`），与被测文件同目录或 `tests/` 目录（实值见 `项目编码规范.md §4 FE-5`）。覆盖**正常路径 + 关键边界/异常路径**（含错误状态渲染、加载态、空数据）。

6. **迭代范围**：迭代期（写→跑→改循环）只跑**改动相关子集**——`vitest run <改动文件路径>`（`testCommand()` 限定到改动相关测试模块）；全量套件留**阶段8 门禁**（`fe-unit-test-ci` / `unit-test-ci`）一次执行。

7. **真实并发用例**（FE 适配）：若声称 UI 状态正确性（如「并发请求下计数无冲突」），须用**真实 HTTP 客户端**（`fetch` 并发或 `Promise.all`）发起多个请求，断言最终状态正确且无竞态条件（不得仅以 mock 单次调用充当并发证据）。

8. 产出 `unit_test/` 下报告，列出覆盖映射（组件/函数 → 测试文件/用例名）。

## 5. 产出物

- vitest 测试模块（落点见 FE-5，命名 `*.test.tsx`/`*.test.ts`，或 spec 约定路径）；
- `../../changes/<变更目录>/unit_test/unit_test_report_vN.md`。

> 报告精简：本 SKILL 产出的报告类产物须满足 `plugins/harness-core/rules/开发流程规范.md` **DF-012**（内容硬约束 + 100 行软自检线 + 证据优先 + 不硬截断）。

## 6. 完成判据

- 被改动组件/hooks/服务均有对应 vitest 用例（覆盖映射成立）；
- 本地确认 = 改动相关子集测试**全绿**（`vitest run` 限定到改动相关模块；实值见绑定声明 `testCommand()` / `HARNESS_CONFIG.yaml`）；全量套件验证归**阶段8 门禁**；
- 为阶段8 提供可执行用例（`total_tests > 0 && passed == total`）；
- 若声称 UI 状态正确性：有真实并发用例（非单次 mock）且断言无竞态。

## 7. 引用

- 栈无关骨架（不复制 · 指回）：`plugins/harness-core/skills/unit-test-write/`（改动驱动 / 覆盖映射 / 真实并发纪律）。
- 绑定声明：`react-vite-binding.md`（实体未迁入 plugin · 待补 · 受控前向引用，见 fe-coding-skill §3；`testCommand()` = `vitest run`）。
- 测试根/命名约定：`plugins/harness-core/rules/项目编码规范.md §4 FE-5`。
- FE 分层 Spec：`.harness/skills/fe-coding-skill/specs/`（消费方项目本地镜像路径 —— 指向项目安装后由 hook 落盘的本地副本；RM-132/133 · 覆盖依据）。
- 下游：`../fe-unit-test-ci/`、`plugins/harness-core/skills/unit-test-ci/`（阶段8）、`plugins/harness-core/skills/expert-reviewer/`（阶段6）。
- vitest 官方文档：https://vitest.dev
- React Testing Library 官方文档：https://testing-library.com/react
