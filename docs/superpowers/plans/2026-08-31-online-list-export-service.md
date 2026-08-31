# 在线列表与导出服务 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在线页进入即展示 AirScript 全量设备列表，远程增删改与配置切换后重新同步；二维码通过统一导出服务以真实名称下载到电脑。

**Architecture:** `OnlineConfigStore` 保存可选配置列表、选中项和旧格式迁移，内置配置固定为只读。`DeviceApi` 扩展 `list` 的请求与结果类型。`SpreadsheetPage` 保持本地 XLS 的延迟导出行为，同时增加返回完整同步表格的远程行操作回调供在线页复用。首页管理唯一的 `HomePageController`，在线页、本地页和导出页共享该控制器，避免导出服务状态分裂。

**Tech Stack:** Flutter Material 3、Dart `http`、现有 `FileServer`、`qr_flutter`、Flutter widget/unit tests。

---

## 文件结构

- 修改 `lib/utils/net_util.dart`：新增列表结果模型和 `DeviceApi.listDevices`。
- 修改 `lib/online/online_config_store.dart`、`lib/online/online_config_page.dart`：实现内置与自定义配置列表、迁移、选择和编辑。
- 修改 `lib/spreadsheet_page.dart`：为远程行保存/删除增加可选回调，不改变本地 XLS 对外接口。
- 修改 `lib/online/online_page.dart`：加载远程列表并将行操作委托给 API，成功后重新拉取。
- 修改 `lib/home_page.dart`、`lib/home_page_view.dart`、`lib/local_page.dart`：创建共享控制器并增加导出入口。
- 创建 `lib/export_page.dart`、修改 `lib/local_page_view.dart`：显示统一的导出服务状态与局域网地址。
- 修改 `lib/home_page_controller.dart`、`lib/network_tools/file_service.dart`：暴露待导出文件名，供页面展示。
- 修改 `lib/qr_create_page.dart`：默认目录和 ZIP 文件名改为 `二维码合计`。
- 修改 `test/net_util_test.dart`、`test/online_page_test.dart`、`test/spreadsheet_page_test.dart`、`test/qr_create_page_test.dart`，创建 `test/export_page_test.dart`。

### Task 1: 在线配置列表与内置保护

**Files:**
- Modify: `test/online_page_test.dart`
- Modify: `lib/online/online_config_store.dart`
- Modify: `lib/online/online_config_page.dart`
- Modify: `lib/online/online_page.dart`

- [ ] **Step 1: 写出内置配置、旧值迁移和确认选择的失败测试**

```dart
test('migrates the legacy config and keeps the built-in config immutable', () async {
  SharedPreferences.setMockInitialValues({
    'online_api_url': 'https://legacy.example.com',
    'online_api_token': 'legacy-token',
  });
  final store = const OnlineConfigStore();
  final configs = await store.loadAll();

  expect(configs.singleWhere((config) => config.isBuiltIn).url,
      'https://www.kdocs.cn/api/v3/ide/file/cjQJmvEX03n2/script/V2-7LfFuITpzY7ymzPf8OfNy7/sync_task');
  expect(configs.singleWhere((config) => !config.isBuiltIn).url,
      'https://legacy.example.com');
  await expectLater(store.delete(OnlineApiConfig.builtInId), throwsStateError);
});

testWidgets('confirms the selected configuration and returns it', (tester) async {
  OnlineApiConfig? returned;
  await tester.pumpWidget(MaterialApp(
    home: Builder(builder: (context) => FilledButton(
      onPressed: () => Navigator.push<OnlineApiConfig>(context,
        MaterialPageRoute(builder: (_) => const OnlineConfigPage()),
      ).then((value) => returned = value),
      child: const Text('打开配置'),
    )),
  ));
  await tester.tap(find.text('打开配置'));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('online-config-select-builtin')));
  await tester.tap(find.byKey(const Key('online-config-confirm')));
  await tester.pumpAndSettle();
  expect(returned?.id, OnlineApiConfig.builtInId);
});
```

- [ ] **Step 2: 运行测试确认列表 API 和控件尚不存在**

Run: `flutter test test/online_page_test.dart`

Expected: 编译失败，提示 `loadAll`、`isBuiltIn`、`online-config-confirm` 或 `online-config-select-builtin` 未定义。

- [ ] **Step 3: 实现配置模型、迁移与存储操作**

```dart
class OnlineApiConfig {
  static const builtInId = 'builtin';
  final String id;
  final String url;
  final String token;
  final bool isBuiltIn;

  const OnlineApiConfig({
    required this.id,
    required this.url,
    required this.token,
    this.isBuiltIn = false,
  });
}

Future<List<OnlineApiConfig>> loadAll();
Future<OnlineApiConfig> load();
Future<OnlineApiConfig> create({required String url, required String token});
Future<OnlineApiConfig> update(OnlineApiConfig config);
Future<void> delete(String id);
Future<void> select(String id);
```

`loadAll` 总是把使用用户提供 URL/Token 的内置项放在第一个位置。首次读取时，把旧的 `online_api_url` 和 `online_api_token` 组合为一条自定义项；若 URL/Token 与内置项相同则不重复创建。列表和选中 ID 使用 JSON 字符串存储在新的偏好键中。`update` 与 `delete` 对内置 ID 抛出 `StateError`；删除活动自定义项后将活动 ID 写为 `builtin`。URL 必须含协议，Token 必须非空。

- [ ] **Step 4: 将配置页改为可选列表与页内编辑弹窗**

```dart
Future<void> _confirmSelection() async {
  final selected = _selected;
  if (selected == null) return;
  await widget.store.select(selected.id);
  if (mounted) Navigator.pop(context, selected);
}

void _select(String? id) {
  if (id != null) setState(() => _selectedId = id);
}

Widget _configTile(OnlineApiConfig config) => ListTile(
  key: Key('online-config-select-${config.id}'),
  leading: Radio<String>(value: config.id, groupValue: _selectedId,
      onChanged: _select),
  title: SelectableText(config.url),
  subtitle: SelectableText('Token: ${config.token}'),
);
```

页面标题保持“接口配置”。内置项显示“内置”标识，不显示编辑或删除按钮。自定义项显示编辑和删除图标；点击“新增配置”或编辑图标时，在当前页面的 `AlertDialog` 中复用 URL 和 Token 输入框，保存后重新读取配置列表。页面底部“确认使用”只对当前选中项生效。

- [ ] **Step 5: 使在线页在确认配置后重新拉取列表**

```dart
final config = await Navigator.push<OnlineApiConfig>(context, route);
if (config == null || !mounted) return;
setState(() => _apiConfig = config);
await _loadList();
```

删除 `online_page.dart` 中的 URL/Token 注释，配置值只保留在配置存储模块。已有的 `_requireConfig` 继续通过 `store.load()` 取得已确认的活动配置。

- [ ] **Step 6: 运行配置测试确认通过**

Run: `flutter test test/online_page_test.dart`

Expected: 退出码 `0`，内置保护、迁移、自定义配置编辑、确认选择和配置切换刷新均通过。

- [ ] **Step 7: 提交配置列表**

```bash
git add lib/online/online_config_store.dart lib/online/online_config_page.dart lib/online/online_page.dart test/online_page_test.dart
git commit -m "feat: manage online API configurations"
```

### Task 2: 列表接口模型

**Files:**
- Modify: `test/net_util_test.dart`
- Modify: `lib/utils/net_util.dart`

- [ ] **Step 1: 写出列表请求与解析的失败测试**

```dart
test('sends list requests and parses all remote rows', () async {
  // 本地 HttpServer 返回 type=list、total=2 和 rows。
  final result = await DeviceApi.listDevices(
    webhook: 'http://${server.address.address}:${server.port}',
    token: 'custom-token',
  );
  expect(receivedBody?['Context'], {
    'argv': {'type': 'list'},
  });
  expect(result.rows, hasLength(2));
  expect(result.rows.first['设备编号'], 'P001');
});
```

- [ ] **Step 2: 运行测试确认缺少 API 而失败**

Run: `flutter test test/net_util_test.dart`

Expected: 编译失败，提示 `DeviceApi.listDevices` 未定义。

- [ ] **Step 3: 实现最小列表模型与 API**

```dart
class DeviceListResult {
  final bool success;
  final String? message;
  final List<Map<String, dynamic>> rows;

  factory DeviceListResult.fromJson(Map<String, dynamic> json) =>
      DeviceListResult._(
        success: json['success'] == true,
        message: json['message'] as String?,
        rows: [
          for (final row in json['rows'] as List? ?? const [])
            Map<String, dynamic>.from(row as Map),
        ],
      );
}

static Future<DeviceListResult> listDevices({
  required String webhook,
  required String token,
}) async => DeviceListResult.fromJson(
  (await _invokeRaw({'type': 'list'}, webhook: webhook, token: token)),
);
```

将 `_invoke` 拆为返回脚本 `result` 的私有 `_invokeRaw`，再由单行结果和列表结果分别解析，保持既有 `queryDevice` 等接口行为。

- [ ] **Step 4: 运行接口测试确认通过**

Run: `flutter test test/net_util_test.dart`

Expected: 退出码 `0`，两个网络层测试通过。

- [ ] **Step 5: 提交接口模型**

```bash
git add lib/utils/net_util.dart test/net_util_test.dart
git commit -m "feat: load online device lists"
```

### Task 3: 表格远程行操作复用

**Files:**
- Modify: `test/spreadsheet_page_test.dart`
- Modify: `lib/spreadsheet_page.dart`

- [ ] **Step 1: 写出远程行保存后不显示本地保存按钮的失败测试**

```dart
testWidgets('uses remote row callbacks without list save action', (tester) async {
  await tester.pumpWidget(_spreadsheetApp(
    table: table,
    onSaveRow: (_, row) async => XlsTable(
      headers: table.headers,
      rows: [row],
    ),
  ));
  expect(find.byTooltip('保存'), findsNothing);
});
```

- [ ] **Step 2: 运行测试确认构造参数未定义而失败**

Run: `flutter test test/spreadsheet_page_test.dart`

Expected: 编译失败，提示 `onSaveRow` 未定义。

- [ ] **Step 3: 实现可选行回调**

```dart
final Future<XlsTable> Function(int? rowIndex, List<String> row)? onSaveRow;
final Future<XlsTable> Function(int rowIndex, List<String> row)? onDeleteRow;
final Future<void> Function(XlsTable table)? onSave;

Future<void> _saveRow(int? rowIndex, List<String> row) async {
  final remoteSave = widget.onSaveRow;
  if (remoteSave != null) {
    final synchronizedTable = await remoteSave(rowIndex, _rowForEditor(row));
    _replaceTable(synchronizedTable);
    return;
  }
  final candidateRows = _rows.map(List<String>.from).toList();
  if (rowIndex == null) {
    candidateRows.add(_rowForEditor(row));
  } else {
    candidateRows[rowIndex] = _rowForEditor(row);
  }
  _replaceTable(XlsTable(headers: _headers, rows: candidateRows));
}
```

将原本必填的 `onSave` 改为可选参数；仅在 `onSave != null && onSaveRow == null` 时展示浮动“保存”按钮。`_replaceTable` 用新的表头和行替换可变列表；删除确认后优先调用 `onDeleteRow` 并替换返回值。远程模式不展示浮动“保存”按钮，仍保留扫码、二维码与新增入口。在线页每次 API 操作成功后重新拉取，再把新的 `XlsTable` 返回，因此 `SpreadsheetPage` 不维护陈旧副本。

- [ ] **Step 4: 运行表格测试确认通过**

Run: `flutter test test/spreadsheet_page_test.dart`

Expected: 退出码 `0`，原有本地保存测试及远程模式测试均通过。

- [ ] **Step 5: 提交表格复用能力**

```bash
git add lib/spreadsheet_page.dart test/spreadsheet_page_test.dart
git commit -m "feat: reuse spreadsheet for remote rows"
```

### Task 4: 在线全量加载与同步

**Files:**
- Modify: `test/online_page_test.dart`
- Modify: `lib/online/online_page.dart`

- [ ] **Step 1: 写出进入即加载与操作后刷新列表的失败测试**

```dart
testWidgets('loads all rows on entry and reloads after an edit', (tester) async {
  var listCalls = 0;
  await tester.pumpWidget(_app(
    onList: () async => _listResult([
      _deviceData(deviceNo: listCalls++ == 0 ? 'P001' : 'P002'),
    ]),
    onModify: (_, __) async => _result(type: 'modify'),
  ));
  await tester.pumpAndSettle();
  expect(find.text('P001'), findsOneWidget);
  // 编辑并保存后，断言 P002 已显示且 listCalls 为 2。
});
```

- [ ] **Step 2: 运行测试确认 `onList` 与列表 UI 未定义而失败**

Run: `flutter test test/online_page_test.dart`

Expected: 编译失败，提示 `OnlinePage.onList` 未定义。

- [ ] **Step 3: 实现在线表格装配与刷新**

```dart
typedef DeviceListCallback = Future<DeviceListResult> Function();

Future<XlsTable> _loadList() async {
  final result = await _listApi();
  if (!result.success) throw DeviceApiException(result.errorMessage);
  final table = XlsTable(
    headers: onlineDeviceHeaders,
    rows: result.rows.map(_mapToRow).toList(),
  );
  if (mounted) setState(() => _table = table);
  return table;
}
```

初始化配置读取完成后调用 `_loadList`。加载成功后由 `OnlinePage` 直接返回配置为远程模式的 `SpreadsheetPage`：`onSaveRow` 和 `onDeleteRow` 分别调用已有 API 后返回 `await _loadList()`；`onExportQrCodes` 传入共享控制器的 `exportQrArchive`；`title` 保持“在线设备”；`appBarActions` 加入接口配置与刷新图标。`SpreadsheetPage` 的 `didUpdateWidget` 在父级表格更新时调用 `_replaceTable`。扫码得到编号后仅定位并打开对应行，未匹配时提示用户。接口配置变更后也重新加载。

- [ ] **Step 4: 运行在线页测试确认通过**

Run: `flutter test test/online_page_test.dart`

Expected: 退出码 `0`，列表首屏加载、增改删刷新、错误保留当前列表均通过。

- [ ] **Step 5: 提交在线同步**

```bash
git add lib/online/online_page.dart test/online_page_test.dart
git commit -m "feat: sync online device list"
```

### Task 5: 共享导出服务与入口

**Files:**
- Modify: `test/home_page_view_test.dart`
- Modify: `test/local_page_view_test.dart`
- Create: `test/export_page_test.dart`
- Modify: `lib/home_page.dart`
- Modify: `lib/home_page_view.dart`
- Modify: `lib/local_page.dart`
- Create: `lib/export_page.dart`
- Modify: `lib/local_page_view.dart`
- Modify: `lib/home_page_controller.dart`
- Modify: `lib/network_tools/file_service.dart`

- [ ] **Step 1: 写出导出入口、服务状态与待导出文件的失败测试**

```dart
testWidgets('shows the export entry', (tester) async {
  await tester.pumpWidget(HomePageView(
    onOnlinePage: () {}, onLocalPage: () {}, onExportPage: () {},
  ));
  expect(find.text('导出'), findsOneWidget);
});

testWidgets('shows a queued export filename', (tester) async {
  await tester.pumpWidget(MaterialApp(
    home: LocalPageView(
      status: '运行中', localIp: '192.168.1.10', port: 8080,
      isRunning: true, hasFiles: false,
      pendingExportFilename: '二维码合计.zip',
      onStart: () {}, onStop: () {}, onOpenFiles: () {},
    ),
  ));
  expect(find.text('二维码合计.zip'), findsOneWidget);
});
```

- [ ] **Step 2: 运行测试确认入口和导出页未定义而失败**

Run: `flutter test test/home_page_view_test.dart test/local_page_view_test.dart test/export_page_test.dart`

Expected: 编译失败，提示 `onExportPage` 或 `ExportPage` 未定义。

- [ ] **Step 3: 实现共享控制器和导出页面**

```dart
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late final HomePageController _controller;

  @override
  void initState() {
    super.initState();
    _controller = HomePageController()..initialize();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}

class ExportPage extends StatelessWidget {
  final HomePageController controller;
}
```

`ExportPage.build` 使用 `AnimatedBuilder(animation: controller)` 并传递 `controller.status`、`controller.localIp`、`controller.isRunning`、`controller.pendingExportFilename` 到 `LocalPageView`。`HomePageView` 增加第三个“导出”按钮。`HomePageController.initialize` 只准备保存目录，`startServer` 仅由服务页的“启动服务”按钮调用。`LocalPage` 接收外部 `HomePageController`，不再自行创建、初始化或释放它。`FileServer` 和 `HomePageController` 暴露 `pendingExportFilename`，`queueExport` 时通知页面；电脑完成下载后清空该名称并通知页面。`LocalPageView` 以可选参数显示“待导出：文件名”，保持状态、地址和启动/停止按钮的原有视觉语言。

- [ ] **Step 4: 运行导出页相关测试确认通过**

Run: `flutter test test/home_page_view_test.dart test/local_page_view_test.dart test/export_page_test.dart`

Expected: 退出码 `0`，入口、服务状态、地址和待导出文件名均被覆盖。

- [ ] **Step 5: 提交导出服务页面**

```bash
git add lib/home_page.dart lib/home_page_view.dart lib/local_page.dart lib/export_page.dart lib/local_page_view.dart lib/home_page_controller.dart lib/network_tools/file_service.dart test/home_page_view_test.dart test/local_page_view_test.dart test/export_page_test.dart
git commit -m "feat: add shared export service page"
```

### Task 6: 二维码真实名称与端到端回归

**Files:**
- Modify: `test/qr_create_page_test.dart`
- Modify: `lib/qr_create_page.dart`
- Modify: `lib/online/online_page.dart`

- [ ] **Step 1: 写出二维码 ZIP 真实名称的失败测试**

```dart
testWidgets('exports QR archive with its business name', (tester) async {
  // 生成后导出。
  expect(exportedName, '二维码合计.zip');
});
```

- [ ] **Step 2: 运行测试确认当前 `A.zip` 导致断言失败**

Run: `flutter test test/qr_create_page_test.dart`

Expected: 失败，实际文件名为 `A.zip`。

- [ ] **Step 3: 使用真实目录和归档名**

```dart
return QrCodeService(Directory('${appDirectory.path}/二维码合计'));
await onExport(archive, '二维码合计.zip');
```

在线页将共享控制器的 `exportQrArchive` 传给远程表格的二维码页面。未运行服务时保留明确错误提示。

- [ ] **Step 4: 运行二维码与全量回归测试**

Run: `flutter test`

Expected: 退出码 `0`，全部测试通过。

- [ ] **Step 5: 运行静态分析并提交最终功能**

Run: `flutter analyze`

Expected: 退出码 `0`，没有错误或警告。

```bash
git add lib/qr_create_page.dart lib/online/online_page.dart test/qr_create_page_test.dart
git commit -m "feat: export QR codes with business name"
```
