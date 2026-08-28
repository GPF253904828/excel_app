# 在线设备表格 CRUD Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 完善 `OnlinePage`，按设备编号查询并展示固定 15 列设备信息，复用 `DeviceEditPage` 完成在线修改和新增，并支持二次确认删除。

**Architecture:** `OnlinePage` 维护查询结果、输入框和操作状态，默认调用现有 `DeviceApi`。页面通过可选回调注入查询、修改、新增、删除函数以便 widget 测试；`DeviceEditPage` 仍负责编辑表单、设备编号确认和保存失败留在编辑页。脚本和网络封装保持不变。

**Tech Stack:** Flutter/Dart、Material widgets、`flutter_test`、现有 `DeviceApi`/`DeviceResult`。

---

### Task 1: 建立在线页行为测试

**Files:**
- Create: `test/online_page_test.dart`
- Reference: `lib/online/online_page.dart`, `lib/device_edit_page.dart`, `lib/utils/net_util.dart`

- [ ] **Step 1: 写失败测试**

覆盖这些可观察行为：

```dart
testWidgets('查询成功后按固定 15 列展示整行数据', ...);
testWidgets('查询失败显示接口消息', ...);
testWidgets('修改编辑后的整行并用原设备编号调用接口', ...);
testWidgets('新增整行并展示接口返回的新设备', ...);
testWidgets('删除二次确认后清空结果但保留输入框', ...);
testWidgets('修改失败时编辑页保持打开', ...);
```

每个测试通过 `OnlinePage` 的可选回调返回 `DeviceResult.fromJson(...)`，不访问真实网络；测试数据覆盖 15 个字段，验证修改/新增发送的 `Map<String, dynamic>` 与页面结果更新。

- [ ] **Step 2: 运行测试确认失败**

运行：`flutter test test/online_page_test.dart`

预期：失败，因为当前页面没有固定列、编辑/新增/删除入口和可注入 API 回调。

### Task 2: 实现在线页状态和查询展示

**Files:**
- Modify: `lib/online/online_page.dart`

- [ ] **Step 1: 添加固定列和测试注入回调**

定义 15 列常量和四种回调类型；`OnlinePage` 增加可选 `onQuery`、`onModify`、`onAdd`、`onDelete`，未传入时分别调用 `DeviceApi` 对应方法。

- [ ] **Step 2: 实现查询状态和数据归一化**

实现 `_query`、`_normalizeData` 和 `_rowToData`：去除输入首尾空格；`success=false` 使用 `errorMessage`；成功结果按固定表头补齐空值；异常不清空已有结果。

- [ ] **Step 3: 构建固定 15 列结果表格**

保留设备编号输入框；结果区域按固定顺序渲染每个字段，查询成功显示“修改”和“删除”，顶部显示“新增设备”；查询成功、失败和接口异常均显示明确状态文本。

- [ ] **Step 4: 运行查询相关测试**

运行：`flutter test test/online_page_test.dart`

预期：查询成功展示和查询失败提示测试通过。

### Task 3: 接入复用编辑器的修改、新增和删除

**Files:**
- Modify: `lib/online/online_page.dart`

- [ ] **Step 1: 实现修改流程**

打开 `DeviceEditPage` 并传入 15 列整行；保存时以查询时的原始设备编号调用修改回调，将整行映射为字段 Map；仅在接口 `success=true` 时使用返回数据更新页面并提示成功，失败抛出异常让编辑页保留并显示错误。

- [ ] **Step 2: 实现新增流程**

打开空白 `DeviceEditPage`；保存时传入整行 Map 调用新增回调；成功后使用接口返回的整行数据更新结果，并把输入框更新为新设备编号；失败不更新结果。

- [ ] **Step 3: 实现删除流程**

查询成功时显示删除按钮；点击后弹出二次确认；确认后以当前查询编号调用删除回调。接口成功时清空结果、保留输入框内容并显示成功提示；业务失败或异常保留结果并显示失败原因。

- [ ] **Step 4: 运行完整在线页测试**

运行：`flutter test test/online_page_test.dart`

预期：查询、修改、新增、删除和失败状态测试全部通过。

### Task 4: 全量验证和变更边界检查

**Files:**
- Verify: `lib/online/air_script`
- Verify: `lib/online/online_page.dart`, `test/online_page_test.dart`

- [ ] **Step 1: 运行完整测试套件**

运行：`flutter test`

预期：退出码为 0，所有测试通过。

- [ ] **Step 2: 运行静态分析和差异检查**

运行：`flutter analyze` 和 `git diff --check`

预期：静态分析无错误，差异检查无空白错误。

- [ ] **Step 3: 确认脚本未修改**

运行：`git diff -- lib/online/air_script`，并检查 `git status --short`。

预期：脚本差异为空；只报告本任务新增/修改的在线页测试与实现，保留用户已有的其他未提交改动。
