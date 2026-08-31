# 二维码二级导出与列表排序 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 固定在线设备表格列序，消除配置页操作重叠，并将二维码导出改为带局域网服务控制的二级页面流程。

**Architecture:** `onlineTableHeaders` 固定 15 个业务字段的优先顺序，并把接口扩展字段追加在后。二维码页在生成 ZIP 后通过可选页面构建回调进入专用 `ExportPage`；该页复用局域网服务状态视图并在用户点击后调用 `HomePageController.exportQrArchive`。首页继续拥有同一控制器，但不显示导出入口。

**Tech Stack:** Flutter Material 3、现有 `HomePageController`、`QrCodeService`、Flutter widget/unit tests。

---

## 文件结构

- 修改 `lib/online/online_page.dart`：固定列表列序，并将二维码导出页构建回调传给表格。
- 修改 `lib/online/online_config_page.dart`：将新增入口从悬浮按钮移至应用栏。
- 修改 `lib/qr_create_page.dart`、`lib/spreadsheet_page.dart`：支持由二维码页打开导出二级页。
- 修改 `lib/export_page.dart`、`lib/local_page_view.dart`：展示二维码 ZIP 并提供“导出二维码”操作。
- 修改 `lib/home_page.dart`、`lib/home_page_view.dart`、`lib/local_page.dart`：移除首页导出入口，并从在线/本地二维码页构造二级导出页。
- 修改 `test/online_page_test.dart`、`test/qr_create_page_test.dart`、`test/export_page_test.dart`、`test/home_page_view_test.dart`。

### Task 1: 固定列序与配置页布局

**Files:**
- Modify: `test/online_page_test.dart`
- Modify: `lib/online/online_page.dart`
- Modify: `lib/online/online_config_page.dart`

- [ ] **Step 1: 写出列序和新增入口位置的失败测试**

```dart
test('orders standard online headers before additional fields', () {
  expect(
    onlineTableHeaders([
      {'设备名称': '设备A', '备注': '扩展字段', '设备编号': 'P001'},
    ]),
    [...onlineDeviceHeaders, '备注'],
  );
});

testWidgets('keeps add and confirm actions separate', (tester) async {
  await tester.pumpWidget(const MaterialApp(home: OnlineConfigPage()));
  await tester.pumpAndSettle();
  expect(find.byKey(const Key('online-config-add')), findsOneWidget);
  expect(find.byType(FloatingActionButton), findsNothing);
  expect(find.byKey(const Key('online-config-confirm')), findsOneWidget);
});
```

- [ ] **Step 2: 运行测试确认缺少列序函数或布局断言失败**

Run: `flutter test test/online_page_test.dart`

Expected: 失败，提示 `onlineTableHeaders` 未定义，或发现配置页仍有悬浮按钮。

- [ ] **Step 3: 实现固定列序与应用栏新增按钮**

```dart
List<String> onlineTableHeaders(List<Map<String, dynamic>> rows) {
  final headers = <String>[...onlineDeviceHeaders];
  for (final row in rows) {
    for (final header in row.keys) {
      if (!headers.contains(header)) headers.add(header);
    }
  }
  return headers;
}
```

`_tableFromRows` 使用该函数构建表头。`OnlineConfigPage` 删除 `floatingActionButton`，在应用栏 `actions` 中加入带 `online-config-add` 键的 `IconButton`，其回调仍为 `_openEditor`；底部“确认使用”不变。

- [ ] **Step 4: 运行测试确认通过**

Run: `flutter test test/online_page_test.dart`

Expected: 退出码 `0`，在线列表和配置列表全部测试通过。

- [ ] **Step 5: 提交列序与配置布局**

```bash
git add lib/online/online_page.dart lib/online/online_config_page.dart test/online_page_test.dart
git commit -m "fix: order online columns and config actions"
```

### Task 2: 二维码二级导出页

**Files:**
- Modify: `test/qr_create_page_test.dart`
- Modify: `test/export_page_test.dart`
- Modify: `lib/qr_create_page.dart`
- Modify: `lib/spreadsheet_page.dart`
- Modify: `lib/export_page.dart`
- Modify: `lib/local_page_view.dart`

- [ ] **Step 1: 写出二维码导出打开二级页的失败测试**

```dart
testWidgets('opens the QR export page after archive generation', (tester) async {
  await tester.pumpWidget(MaterialApp(
    home: QrCreatePage(
      headers: const ['设备编号', '设备名称'],
      rows: const [['P001', '设备A']],
      service: _FakeQrCodeService(),
      exportPageBuilder: (_, filename) => Scaffold(body: Text(filename)),
    ),
  ));
  await tester.tap(find.text('生成'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('导出'));
  await tester.pumpAndSettle();
  expect(find.text('二维码合计.zip'), findsOneWidget);
});

testWidgets('shows an enabled QR export action', (tester) async {
  await tester.pumpWidget(MaterialApp(
    home: ExportPage(
      controller: HomePageController(),
      archive: Uint8List.fromList([0x50, 0x4B]),
      filename: '二维码合计.zip',
    ),
  ));
  expect(find.text('导出二维码'), findsOneWidget);
});
```

- [ ] **Step 2: 运行测试确认页面构建回调和 ZIP 参数未定义**

Run: `flutter test test/qr_create_page_test.dart test/export_page_test.dart`

Expected: 编译失败，提示 `exportPageBuilder`、`archive` 或 `filename` 未定义。

- [ ] **Step 3: 传递 ZIP 并构建二级导出页**

```dart
typedef QrExportPageBuilder = Widget Function(
  Uint8List archive,
  String filename,
);

final QrExportPageBuilder? exportPageBuilder;

if (exportPageBuilder != null) {
  await Navigator.push<void>(
    context,
    MaterialPageRoute(
      builder: (_) => exportPageBuilder(archive, '二维码合计.zip'),
    ),
  );
  return;
}
```

`SpreadsheetPage` 增加同名回调并传给 `QrCreatePage`。`ExportPage` 改为有状态页面，接收 ZIP 字节和文件名；它通过 `LocalPageView` 的可选 `extraAction` 展示“导出二维码”按钮。点击时先 `await controller.startServer()`，若服务仍未运行则显示控制器状态；否则调用 `controller.exportQrArchive(archive, filename)`，并显示已排队状态。按钮始终可点击，不会因为服务未启动而失效。

- [ ] **Step 4: 运行二维码与导出页测试确认通过**

Run: `flutter test test/qr_create_page_test.dart test/export_page_test.dart`

Expected: 退出码 `0`，二维码 ZIP 进入二级页，导出页展示服务控制、地址、状态和导出按钮。

- [ ] **Step 5: 提交二维码二级导出**

```bash
git add lib/qr_create_page.dart lib/spreadsheet_page.dart lib/export_page.dart lib/local_page_view.dart test/qr_create_page_test.dart test/export_page_test.dart
git commit -m "feat: open QR export page"
```

### Task 3: 移除首页导出入口并接入共享控制器

**Files:**
- Modify: `test/home_page_view_test.dart`
- Modify: `lib/home_page.dart`
- Modify: `lib/home_page_view.dart`
- Modify: `lib/local_page.dart`
- Modify: `lib/online/online_page.dart`

- [ ] **Step 1: 写出首页不显示导出入口的失败测试**

```dart
testWidgets('renders online and local actions without a home export action',
    (tester) async {
  await tester.pumpWidget(MaterialApp(
    home: HomePageView(onOnlinePage: () {}, onLocalPage: () {}),
  ));
  expect(find.text('在线'), findsOneWidget);
  expect(find.text('本地'), findsOneWidget);
  expect(find.text('导出'), findsNothing);
});
```

- [ ] **Step 2: 运行测试确认当前首页仍需要导出回调**

Run: `flutter test test/home_page_view_test.dart`

Expected: 编译失败，提示缺少 `onExportPage` 参数，或断言发现首页导出按钮。

- [ ] **Step 3: 删除首页入口并从表格构造二维码导出页**

```dart
HomePageView(
  onOnlinePage: _showOnlinePage,
  onLocalPage: _showLocalPage,
)
```

删除 `HomePageView.onExportPage` 与 `_showExportPage`。`HomePage` 把
`(archive, filename) => ExportPage(controller: _controller, archive: archive, filename: filename)`
传给 `OnlinePage`；`LocalPage` 把同一构造回调传给本地 `SpreadsheetPage`。`OnlinePage` 再将该回调传给远程 `SpreadsheetPage`，使线上与本地列表的二维码都走相同二级导出流程。

- [ ] **Step 4: 运行首页、在线和表格测试确认通过**

Run: `flutter test test/home_page_view_test.dart test/online_page_test.dart test/spreadsheet_page_test.dart`

Expected: 退出码 `0`，首页无导出入口，二维码页仍可从两类表格打开。

- [ ] **Step 5: 执行全量验证并提交**

Run: `flutter test && flutter analyze`

Expected: 两个命令均以退出码 `0` 结束。

```bash
git add lib/home_page.dart lib/home_page_view.dart lib/local_page.dart lib/online/online_page.dart test/home_page_view_test.dart
git commit -m "fix: move export to QR workflow"
```
