# CI 验证结果 · ci_result

> 阶段8 产出。由 `unit-test-ci` 生成。

## 门禁判定（必须全真）
| 条件 | 值 | 是否满足 |
|---|---|---|
| `status == SUCCESS` | {{SUCCESS/FAILURE}} | {{是/否}} |
| `total_tests > 0` | {{n}} | {{是/否}} |
| `passed == total` | {{passed}}/{{total}} | {{是/否}} |

## 结论
- 门禁：{{通过 / 不通过}}
- 不通过回退：用例数 0 → 阶段5；pytest/构建失败 → 阶段3（见 `开发流程规范.md` §2.1）
- 默认验证命令（对比测试 A 轮）：`cd harnessdemo/price-service && pytest -q`（B 轮在 `demo/price-service/` 人工验收）
- CI 链接：{{...}}
