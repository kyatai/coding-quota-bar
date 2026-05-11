# Fix: 统计图表时间顺序错误

## TL;DR

> **Quick Summary**: 图表 X 轴时间标签未按时间排序，导致柱状图时间轴错乱。在数据源和展示层添加排序。
> 
> **Deliverables**:
> - 修复后的 `src/providers/zhipu.ts`（3 个 builder 方法排序）
> - 修复后的 `src/renderer/src/components/TokenChart.vue`（labels 排序 + 精确匹配）
> - 修复后的 `src/renderer/src/components/McpChart.vue`（labels 排序）
> 
> **Estimated Effort**: Quick
> **Parallel Execution**: YES - 2 waves
> **Critical Path**: Task 1 → Task 2+3 → F1

---

## Context

### Problem
`buildModelHistory` 按**模型分组**输出 records，不是按时间排序。TokenChart/McpChart 的 labels 提取依赖 records 遍历顺序，没有显式排序。数据匹配用 `endsWith` 字符串匹配，脆弱且可能误匹配。

### Fix Strategy
**在数据源头排序，在展示层防御性排序，数据匹配改为精确查找。**

---

## Verification Strategy

- **Test Decision**: 无现有测试框架，通过 Agent QA 验证
- **QA Policy**: 构建 + 代码审查验证

---

## TODOs

- [ ] 1. 修复 `src/providers/zhipu.ts` — 三个 builder 方法添加排序

  **What to do**:
  - `buildUsageHistory` (line 125-133): 在 `return` 前加 `result.sort((a, b) => a.date.localeCompare(b.date))`
  - `buildToolHistory` (line 135-142): 在 `return` 前加 `result.sort((a, b) => a.date.localeCompare(b.date))`
  - `buildModelHistory` (line 144-158): 在 `return records` 前加 `records.sort((a, b) => a.date.localeCompare(b.date) || a.model.localeCompare(b.model))`

  **Must NOT do**:
  - 不要改动 API 请求逻辑或数据结构
  - 不要引入新依赖

  **Recommended Agent Profile**:
  - **Category**: `quick`
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 1
  - **Blocks**: Task 2, Task 3
  - **Blocked By**: None

  **References**:
  - `src/providers/zhipu.ts:125-158` — 三个 builder 方法的完整实现
  - 排序方式: `a.date.localeCompare(b.date)` — date 格式为 ISO 片段（`2026-04-23T14` 或 `2026-04-23`），字符串比较等价于时间顺序

  **Acceptance Criteria**:
  - [ ] `buildUsageHistory` 返回的数组按 date 升序
  - [ ] `buildToolHistory` 返回的数组按 date 升序
  - [ ] `buildModelHistory` 返回的数组按 date 升序，同日期按 model 排序
  - [ ] `npm run build` 无 TypeScript 错误

  **QA Scenarios**:
  ```
  Scenario: 构建验证
    Tool: Bash
    Steps:
      1. npm run build
      2. 检查输出无 error
    Expected Result: 构建成功，0 errors
    Evidence: .sisyphus/evidence/task-1-build.txt

  Scenario: 代码审查 - 确认排序添加
    Tool: Read
    Steps:
      1. 读取 src/providers/zhipu.ts
      2. 确认 buildUsageHistory、buildToolHistory、buildModelHistory 三个方法末尾有 .sort()
    Expected Result: 三个方法都有排序
    Evidence: .sisyphus/evidence/task-1-sort-added.txt
  ```

  **Commit**: YES (group with Task 2, 3)
  - Message: `fix(chart): sort chart data chronologically and use precise label matching`
  - Files: `src/providers/zhipu.ts`, `src/renderer/src/components/TokenChart.vue`, `src/renderer/src/components/McpChart.vue`

- [ ] 2. 修复 `src/renderer/src/components/TokenChart.vue` — labels 排序 + 精确匹配

  **What to do**:
  - line 23: labels 提取后排序:
    ```js
    const labels = [...new Set(records.map(r => r.date.length === 13 ? r.date.slice(11) : r.date.slice(5)))].sort()
    ```
  - line 24: 数据匹配从 `endsWith` 改为精确 Map 查找:
    ```js
    // 构建 (label, model) -> used 的 Map
    const dataMap = new Map<string, number>()
    for (const r of records) {
      const l = r.date.length === 13 ? r.date.slice(11) : r.date.slice(5)
      dataMap.set(`${l}::${r.model}`, r.used)
    }
    // datasets 中用 dataMap.get(`${l}::${model}`) ?? 0
    ```

  **Must NOT do**:
  - 不改变图表视觉样式
  - 不改变 chartOptions

  **Recommended Agent Profile**:
  - **Category**: `quick`
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: YES (after Task 1)
  - **Parallel Group**: Wave 2 (with Task 3)
  - **Blocks**: None
  - **Blocked By**: Task 1

  **References**:
  - `src/renderer/src/components/TokenChart.vue:18-26` — barData computed 完整实现
  - date 格式: 1d = `2026-04-23T14` (13 chars, slice(11) 得 `14`), 7d/30d = `2026-04-23` (10 chars, slice(5) 得 `04-23`)

  **Acceptance Criteria**:
  - [ ] labels 数组显式 `.sort()` 过
  - [ ] 不再使用 `endsWith` 做数据匹配，改为 Map 精确查找
  - [ ] 图表功能和之前一样，只是时间顺序正确了

  **QA Scenarios**:
  ```
  Scenario: 代码审查 - 确认 labels 排序
    Tool: Read
    Steps:
      1. 读取 TokenChart.vue
      2. 确认 labels 有 .sort()
      3. 确认数据匹配使用 Map 而非 endsWith
    Expected Result: labels 已排序，使用 Map 匹配
    Evidence: .sisyphus/evidence/task-2-token-chart-fix.txt
  ```

  **Commit**: YES (group with Task 1, 3)

- [ ] 3. 修复 `src/renderer/src/components/McpChart.vue` — labels 排序

  **What to do**:
  - line 19: labels 添加排序:
    ```js
    const labels = computed(() => 
      records.value.map(r => r.date.length === 13 ? r.date.slice(11) : r.date.slice(5))
    )
    ```
    改为:
    ```js
    const rawLabels = computed(() => 
      records.value.map(r => r.date.length === 13 ? r.date.slice(11) : r.date.slice(5))
    )
    const labels = computed(() => [...new Set(rawLabels.value)].sort())
    ```
  - 注意: McpChart 的 `records.value.map(r => ...)` 如果有重复日期（不太可能但防御性），需要去重

  **Must NOT do**:
  - 不改变图表视觉样式

  **Recommended Agent Profile**:
  - **Category**: `quick`
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: YES (after Task 1)
  - **Parallel Group**: Wave 2 (with Task 2)
  - **Blocks**: None
  - **Blocked By**: Task 1

  **References**:
  - `src/renderer/src/components/McpChart.vue:18-28` — records/labels/barData 完整实现

  **Acceptance Criteria**:
  - [ ] labels 显式排序过
  - [ ] 如果原始 labels 有重复，已去重

  **QA Scenarios**:
  ```
  Scenario: 代码审查 - 确认 labels 排序
    Tool: Read
    Steps:
      1. 读取 McpChart.vue
      2. 确认 labels 有 .sort()
    Expected Result: labels 已排序
    Evidence: .sisyphus/evidence/task-3-mcp-chart-fix.txt
  ```

  **Commit**: YES (group with Task 1, 2)

---

## Final Verification Wave

- [ ] F1. **Build + Lint 验证** — `unspecified-high`
  运行 `npm run build`，确认无 TypeScript 编译错误。检查三个修改文件的逻辑正确性。
  Output: `Build [PASS/FAIL] | VERDICT`

---

## Commit Strategy

- **1 commit**: `fix(chart): sort chart data chronologically and use precise label matching`
  - Files: `src/providers/zhipu.ts`, `src/renderer/src/components/TokenChart.vue`, `src/renderer/src/components/McpChart.vue`
  - Pre-commit: `npm run build`

---

## Success Criteria

### Verification Commands
```bash
npm run build  # Expected: 成功构建，无错误
```

### Final Checklist
- [ ] zhipu.ts 三个 builder 方法输出按时间排序
- [ ] TokenChart labels 排序 + Map 精确匹配（无 endsWith）
- [ ] McpChart labels 排序 + 去重
- [ ] 构建成功
