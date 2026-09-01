# 在线设备只读查看 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在首页提供在线扫码和在线查看全部，使线上设备信息只能查看、不能编辑，同时允许在线列表导出二维码。

**Architecture:** 首页负责发起扫码和实时 `query` 请求，查询成功后进入新的只读详情页。`OnlinePage` 保留分页和刷新，但以只读模式配置 `SpreadsheetPage`；通用表格的默认编辑模式不变，因此本地 Excel 工作流不受影响。

**Tech Stack:** Flutter、Dart、`mobile_scanner`、HTTP/AirScript、`flutter_test`。

---

## 文件结构

- Create: `lib/device_detail_page.dart` - 只读设备详情展示。
- Create: `test/device_detail_page_test.dart` - 详情页展示测试。
- Modify: `lib/spreadsheet_page.dart` - 添加可选只读模式和查看回调。
- Modify: `test/spreadsheet_page_test.dart` - 覆盖只读表格行为，保留默认编辑行为。
- Modify: `lib/online/online_page.dart` - 在只读模式下关闭写入回调并打开详情。
- Modify: `test/online_page_test.dart` - 覆盖在线列表的只读行为。
- Modify: `lib/home_page_view.dart` - 首页增加在线扫码和在线查看全部入口。
- Modify: `lib/home_page.dart` - 处理扫码、实时查询、错误提示和只读详情跳转。
- Modify: `test/home_page_view_test.dart` - 覆盖首页入口和实时扫码查询。

### Task 1: 只读详情页

**Files:**
- Create: `lib/device_detail_page.dart`
- Create: `test/device_detail_page_test.dart`

- [ ] **Step 1: 写入失败测试**

```dart
testWidgets('shows every returned device field without editable controls',
    (tester) async {
  await tester.pumpWidget(
    const MaterialApp(
      home: DeviceDetailPage(
        data: <String, dynamic>{
          '设备编号': 'P001',
          '设备名称': '设备A',
          '计量日期': '2026-09-01',
        },
      ),
    ),
  );

  expect(find.text('设备详情'), findsOneWidget);
  expect(find.text('设备编号'), findsOneWidget);
  expect(find.text('P001'), findsOneWidget);
  expect(find.text('计量日期'), findsOneWidget);
  expect(find.text('2026-09-01'), findsOneWidget);
  expect(find.byType(TextField), findsNothing);
  expect(find.text('保存'), findsNothing);
});
```

- [ ] **Step 2: 运行测试并确认失败原因是页面尚不存在**

Run: `flutter test test/device_detail_page_test.dart`

Expected: 编译失败，提示 `DeviceDetailPage` 未定义。

- [ ] **Step 3: 实现最小只读详情页**

```dart
/// 展示一条设备记录的只读字段和值。
class DeviceDetailPage extends StatelessWidget {
  final Map<String, dynamic> data;

  const DeviceDetailPage({super.key, required this.data});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('设备详情')),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            for (final entry in data.entries)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(entry.key, style: const TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text(entry.value?.toString() ?? ''),
                  ],
                ),
              ),
          ],
        ),
      );
}
```

- [ ] **Step 4: 运行测试并确认通过**

Run: `flutter test test/device_detail_page_test.dart`

Expected: `All tests passed!`

### Task 2: 为通用表格增加只读模式

**Files:**
- Modify: `lib/spreadsheet_page.dart:18-175,247-288,425-503,659-683`
- Modify: `test/spreadsheet_page_test.dart:224-324`

- [ ] **Step 1: 写入失败测试**

在 `_spreadsheetApp` 增加 `readOnly` 和 `onViewRow` 参数，并新增以下测试：

```dart
testWidgets('read-only table hides editing controls and opens its view callback',
    (tester) async {
  List<String>? viewedHeaders;
  List<String>? viewedRow;
  await tester.pumpWidget(_spreadsheetApp(
    table: XlsTable(
      headers: const ['设备编号', '计量日期'],
      rows: const [
        ['P001', '2026-09-01'],
      ],
    ),
    readOnly: true,
    onViewRow: (headers, row) async {
      viewedHeaders = headers;
      viewedRow = row;
    },
  ));

  expect(find.byTooltip('新增一行'), findsNothing);
  expect(find.byTooltip('生成二维码'), findsNothing);
  expect(find.byTooltip('扫码二维码'), findsNothing);
  await tester.tap(find.text('P001'));
  await tester.pump();
  expect(viewedHeaders, ['设备编号', '计量日期']);
  expect(viewedRow, ['P001', '2026-09-01']);
});
```

- [ ] **Step 2: 运行测试并确认失败原因是只读参数未定义**

Run: `flutter test test/spreadsheet_page_test.dart`

Expected: 编译失败，提示 `readOnly` 或 `onViewRow` 未定义。

- [ ] **Step 3: 实现最小只读分支**

在 `SpreadsheetPage` 增加下列 API，默认值保持现有本地编辑行为：

```dart
typedef SpreadsheetRowViewCallback = Future<void> Function(
  List<String> headers,
  List<String> row,
);

final bool readOnly;
final SpreadsheetRowViewCallback? onViewRow;
```

将行点击行为改为：只读模式调用 `onViewRow` 并传递副本；默认模式继续调用 `_openEditor`。只读模式下不构建顶部的“新增一行”图标；仅当传入二维码导出构造器时保留“生成二维码”图标；不构建扫码和保存浮动按钮，并将数据行 `onLongPress` 设为 `null`。只读模式仅在传入 `onViewRow` 时使行可点击。

- [ ] **Step 4: 运行测试并确认通过**

Run: `flutter test test/spreadsheet_page_test.dart`

Expected: `All tests passed!`，包括已有本地新增、编辑、删除、扫码和二维码测试。

### Task 3: 在线列表切换为只读详情

**Files:**
- Modify: `lib/online/online_page.dart:1-12,72-91,438-458`
- Modify: `test/online_page_test.dart`

- [ ] **Step 1: 写入失败测试**

让测试辅助方法接受 `readOnly`，并新增：

```dart
testWidgets('read-only online list opens details without editing actions',
    (tester) async {
  await _pumpWidget(tester, _app(
    readOnly: true,
    onList: ({required start, required limit}) async => _listResult(
      [
        <String, dynamic>{
          '设备编号': 'P001',
          '设备名称': '设备A',
          '设备状态': '正常使用',
          '计量日期': '2026-09-01',
        },
      ],
      total: 1,
      start: start,
      limit: limit,
    ),
  ));

  await tester.pumpAndSettle();
  expect(find.byTooltip('新增一行'), findsNothing);
  expect(find.byTooltip('生成二维码'), findsOneWidget);
  expect(find.byTooltip('扫码二维码'), findsNothing);
  await tester.tap(find.text('P001'));
  await tester.pumpAndSettle();
  expect(find.text('设备详情'), findsOneWidget);
  expect(find.text('2026-09-01'), findsOneWidget);
  expect(find.byType(DeviceEditPage), findsNothing);
});
```

- [ ] **Step 2: 运行测试并确认失败原因是 `OnlinePage.readOnly` 未定义**

Run: `flutter test test/online_page_test.dart`

Expected: 编译失败，提示 `readOnly` 未定义。

- [ ] **Step 3: 实现只读在线列表**

在 `OnlinePage` 增加 `final bool readOnly;`，默认值为 `false` 以保持注入回调测试和非首页调用方的兼容性。只读模式下：

```dart
onSaveRow: widget.readOnly ? null : _saveRemoteRow,
onDeleteRow: widget.readOnly ? null : _deleteRemoteRow,
readOnly: widget.readOnly,
onViewRow: widget.readOnly ? _openReadOnlyDetail : null,
qrExportPageBuilder: widget.qrExportPageBuilder,
```

实现 `_openReadOnlyDetail(headers, row)`，用表头和单元格构造字段映射，然后通过 `Navigator.push` 打开 `DeviceDetailPage`。保留接口配置、刷新、下拉刷新和分页加载。

- [ ] **Step 4: 运行测试并确认通过**

Run: `flutter test test/online_page_test.dart test/spreadsheet_page_test.dart test/device_detail_page_test.dart`

Expected: `All tests passed!`

### Task 4: 首页增加在线扫码和在线查看全部

**Files:**
- Modify: `lib/home_page_view.dart:4-48`
- Modify: `lib/home_page.dart:1-65`
- Modify: `test/home_page_view_test.dart`

- [ ] **Step 1: 写入失败测试**

将 `HomePageView` 测试的回调拆为 `onOnlineScan`、`onOnlineList`、`onLocalPage`。在测试文件中导入 `device_detail_page.dart`、`device_edit_page.dart`、`online_config_store.dart`、`net_util.dart`、`mobile_scanner.dart` 和 `shared_preferences.dart`，在 `setUp` 中调用 `SharedPreferences.setMockInitialValues(<String, Object>{})`。复制现有扫码测试的 `_mockScannerChannel` 辅助方法，并新增首页实时查询测试：

```dart
testWidgets('online scan queries the current remote device before showing details',
    (tester) async {
  _mockScannerChannel();
  final requestedNumbers = <String>[];
  await tester.pumpWidget(MaterialApp(
    home: HomePage(
      onQuery: (deviceNo, config) async {
        requestedNumbers.add(deviceNo);
        return DeviceResult.fromJson({
          'success': true,
          'data': {
            '设备编号': deviceNo,
            '计量日期': '2026-09-01',
          },
        });
      },
    ),
  ));

  await tester.tap(find.text('在线扫码'));
  await tester.pumpAndSettle();
  tester.widget<MobileScanner>(find.byType(MobileScanner)).onDetect(
    BarcodeCapture(barcodes: [const Barcode(rawValue: 'P001')]),
  );
  await tester.pumpAndSettle();

  expect(requestedNumbers, ['P001']);
  expect(find.text('设备详情'), findsOneWidget);
  expect(find.text('2026-09-01'), findsOneWidget);
  expect(find.byType(DeviceEditPage), findsNothing);
});
```

另增失败分支：`DeviceResult.fromJson({'success': false, 'message': '未找到设备'})` 后，断言不打开 `DeviceDetailPage`。

- [ ] **Step 2: 运行测试并确认失败原因是首页入口和查询注入点未定义**

Run: `flutter test test/home_page_view_test.dart`

Expected: 编译失败，提示 `onOnlineScan`、`onOnlineList` 或 `HomePage.onQuery` 未定义。

- [ ] **Step 3: 实现首页入口和实时查询**

将 `HomePageView` 的“在线”按钮拆为：

```dart
FilledButton.icon(
  onPressed: onOnlineScan,
  icon: const Icon(Icons.document_scanner_outlined),
  label: const Text('在线扫码'),
),
OutlinedButton.icon(
  onPressed: onOnlineList,
  icon: const Icon(Icons.cloud_outlined),
  label: const Text('在线查看全部'),
),
```

在 `HomePage` 添加可替换的查询回调：

```dart
typedef OnlineDeviceQueryCallback = Future<DeviceResult> Function(
  String deviceNo,
  OnlineApiConfig config,
);

final OnlineConfigStore configStore;
final OnlineDeviceQueryCallback? onQuery;
```

`_scanOnlineDevice` 必须依序：打开 `ScannerPage`、跳过取消结果、读取当前配置、调用注入回调或 `DeviceApi.queryDevice`、校验 `result.success` 和 `result.data`、最后打开 `DeviceDetailPage`。任一步失败时仅调用 `ToastUtil.showCenter` 提示并停留在首页。`_showOnlineList` 打开 `OnlinePage(readOnly: true)` 并传入现有 `ExportPage` 构造器，使在线列表可导出二维码。

- [ ] **Step 4: 运行测试并确认通过**

Run: `flutter test test/home_page_view_test.dart test/online_page_test.dart test/spreadsheet_page_test.dart test/device_detail_page_test.dart`

Expected: `All tests passed!`

### Task 5: 整体验证

**Files:**
- Verify: `lib/home_page.dart`
- Verify: `lib/home_page_view.dart`
- Verify: `lib/online/online_page.dart`
- Verify: `lib/spreadsheet_page.dart`
- Verify: `lib/device_detail_page.dart`

- [ ] **Step 1: 格式化修改文件**

Run: `dart format lib/home_page.dart lib/home_page_view.dart lib/online/online_page.dart lib/spreadsheet_page.dart lib/device_detail_page.dart test/home_page_view_test.dart test/online_page_test.dart test/spreadsheet_page_test.dart test/device_detail_page_test.dart`

Expected: 格式化完成且只涉及本功能文件。

- [ ] **Step 2: 运行目标测试集**

Run: `flutter test test/home_page_view_test.dart test/online_page_test.dart test/spreadsheet_page_test.dart test/device_detail_page_test.dart`

Expected: `All tests passed!`

- [ ] **Step 3: 静态检查与变更检查**

Run: `flutter analyze`

Run: `git diff --check`

Expected: 新功能文件无分析错误，变更无空白错误。若全库分析受现有未提交的二维码测试改动阻塞，记录该既有失败并报告，不修改该无关文件。

- [ ] **Step 4: 不创建提交**

保留所有改动在工作区。项目规则禁止在未获明确请求时执行 `git commit`。

## 增量要求（2026-09-01）

- 扫码查询期间，`HomePageView.isOnlineLoading` 显示“正在获取数据...”遮罩并禁用入口；`HomePage._scanOnlineDevice` 在成功、失败和异常路径都通过 `finally` 恢复状态。
- `HomePage._showOnlineList` 继续传入现有 `ExportPage` 构造器，`OnlinePage(readOnly: true)` 将其传递到 `SpreadsheetPage`，因此只读列表保留二维码生成和导出。
- `OnlinePage._tableActions` 在 `readOnly` 时省略 URL/Token 设置图标，只保留刷新图标；列表的分页和刷新请求不变。
- 新增测试覆盖加载提示、只读列表二维码入口存在以及接口设置入口隐藏；全量 `flutter test` 和 `flutter analyze` 必须继续通过。
