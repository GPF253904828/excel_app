# Spreadsheet QR Scan and Device Editing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在移动端表格页通过相机扫码设备二维码，定位并编辑对应设备，或通过统一编辑页新增设备，保存成功后立即更新外部列表。

**Architecture:** `ScannerPage` 只负责相机和返回二维码文本；`DeviceEditPage` 负责动态表单、设备编码二次确认和保存状态；`SpreadsheetPage` 负责查找行、构造候选表格、调用现有 `onSave` 回调，并在外部保存成功后替换或追加本地行。现有二维码生成文件和导出流程保持不变。

**Tech Stack:** Flutter 3.7.12、Dart 2.19.6、`mobile_scanner: ^3.5.7`、现有 `XlsTable`、`ToastUtil` 和文件导出回调。

---

## File Map

- Create `lib/scanner_page.dart`: 相机预览、首个有效二维码结果、扫码错误展示和页面返回。
- Create `lib/device_edit_page.dart`: 动态设备字段表单、已有设备编码只读/二次确认、保存回调和输入生命周期。
- Modify `lib/spreadsheet_page.dart`: 扫码入口、统一编辑页入口、设备编号查找、行替换/追加和保存失败处理；删除旧的单元格编辑弹窗逻辑。
- Modify `pubspec.yaml`: 固定 `mobile_scanner` 版本为 `^3.5.7`，保留当前已有依赖。
- Modify `pubspec.lock`: 由 `flutter pub get` 更新，不手工编辑。
- Modify `android/app/src/main/AndroidManifest.xml`: 声明相机权限。
- Modify `ios/Runner/Info.plist`: 声明相机用途文案。
- Modify `test/spreadsheet_page_test.dart`: 覆盖扫码定位、找不到、统一编辑、新增、保存失败和设备编码确认。
- Create `test/device_edit_page_test.dart`: 覆盖动态字段、只读编码、二次确认和保存结果。
- Create `test/scanner_page_test.dart`: 覆盖二维码文本提取、空值忽略和页面可构建。

工作区中已有但尚未提交的 `lib/qr_code_service.dart`、`lib/qr_create_page.dart` 及对应测试属于既有改动，本计划不重写、不删除，也不把它们混入扫码编辑任务的提交。

### Task 1: Lock scanner dependency and camera permissions

**Files:**
- Modify: `pubspec.yaml:35`
- Modify: `android/app/src/main/AndroidManifest.xml`
- Modify: `ios/Runner/Info.plist`
- Modify: `pubspec.lock` (generated)

- [ ] **Step 1: Pin the dependency to the installed Dart-compatible version.**

Change the dependency entry to:

```yaml
  mobile_scanner: ^3.5.7
```

Keep the existing `archive` and `qr_flutter` entries unchanged.

- [ ] **Step 2: Declare Android camera access.**

Add this permission alongside the existing network permissions:

```xml
<uses-permission android:name="android.permission.CAMERA" />
```

- [ ] **Step 3: Declare iOS camera usage.**

Add this key inside the main `<dict>` in `ios/Runner/Info.plist`:

```xml
<key>NSCameraUsageDescription</key>
<string>使用相机扫码设备二维码</string>
```

- [ ] **Step 4: Resolve dependencies and verify the platform files.**

Run:

```bash
flutter pub get
flutter analyze
```

Expected: dependency resolution succeeds, `pubspec.lock` records `mobile_scanner` version `3.5.7`, and analyzer output contains no new errors.

- [ ] **Step 5: Commit only dependency and permission changes.**

```bash
git add pubspec.yaml pubspec.lock android/app/src/main/AndroidManifest.xml ios/Runner/Info.plist
git commit -m "feat: add camera permission for QR scanning"
```

### Task 2: Build the reusable device editor

**Files:**
- Create: `lib/device_edit_page.dart`
- Create: `test/device_edit_page_test.dart`

- [ ] **Step 1: Write failing widget tests for the editor contract.**

Create tests with these behaviors:

```dart
testWidgets('renders one editable field for every header and returns all values',
    (tester) async {
  List<String>? savedRow;
  await tester.pumpWidget(MaterialApp(
    home: DeviceEditPage(
      headers: const ['设备编号', '设备名称', '型号'],
      initialRow: const ['', '', ''],
      isNew: true,
      onSave: (row) async {
        savedRow = row;
      },
    ),
  ));

  await tester.enterText(find.byKey(const Key('field-设备编号')), 'P002');
  await tester.enterText(find.byKey(const Key('field-设备名称')), '设备B');
  await tester.enterText(find.byKey(const Key('field-型号')), '型号B');
  await tester.tap(find.text('保存'));
  await tester.pumpAndSettle();

  expect(savedRow, ['P002', '设备B', '型号B']);
});

testWidgets('requires confirmation before enabling an existing device code',
    (tester) async {
  await tester.pumpWidget(MaterialApp(
    home: DeviceEditPage(
      headers: const ['设备编号', '设备名称'],
      initialRow: const ['P001', '设备A'],
      isNew: false,
      onSave: (_) async {},
    ),
  ));

  expect(tester.widget<TextField>(find.byKey(const Key('field-设备编号'))).enabled,
      isFalse);
  await tester.tap(find.byTooltip('修改设备编码'));
  await tester.pump();
  expect(find.text('确认修改设备编码'), findsOneWidget);
  await tester.tap(find.text('确认修改'));
  await tester.pump();
  expect(tester.widget<TextField>(find.byKey(const Key('field-设备编号'))).enabled,
      isTrue);
});
```

Add a test that tapping `取消` in the confirmation leaves the field disabled.

- [ ] **Step 2: Run the editor tests and verify the expected missing-symbol failure.**

Run:

```bash
flutter test test/device_edit_page_test.dart
```

Expected: FAIL because `DeviceEditPage` does not exist.

- [ ] **Step 3: Implement the minimal editor page.**

Define this public contract:

```dart
class DeviceEditPage extends StatefulWidget {
  final List<String> headers;
  final List<String> initialRow;
  final bool isNew;
  final Future<void> Function(List<String> row) onSave;

  const DeviceEditPage({
    super.key,
    required this.headers,
    required this.initialRow,
    required this.isNew,
    required this.onSave,
  });
}
```

In `initState`, create one `TextEditingController` per header, padding missing initial cells with empty strings. Render each field with key `field-<header>`. The `设备编号` field uses `enabled: widget.isNew || _deviceNumberEditable`; existing rows show an `IconButton` with tooltip `修改设备编码` that opens an `AlertDialog` titled `确认修改设备编码`, explains that changing the code may affect row matching, and only enables the field when `确认修改` is selected. The save button collects controllers in header order, awaits `widget.onSave(row)`, and pops only after the callback succeeds; exceptions show `保存失败: <error>` and keep all controllers and the page mounted. Dispose every controller in `dispose`.

Add function-level comments for the page lifecycle, confirmation flow, row collection, and save handling.

- [ ] **Step 4: Run the editor tests and verify they pass.**

Run:

```bash
flutter test test/device_edit_page_test.dart
```

Expected: all editor tests pass, including the save-failure test that confirms the page remains visible with its entered values.

- [ ] **Step 5: Commit the editor independently.**

```bash
git add lib/device_edit_page.dart test/device_edit_page_test.dart
git commit -m "feat: add device edit page"
```

### Task 3: Add the camera scanner page

**Files:**
- Create: `lib/scanner_page.dart`
- Create: `test/scanner_page_test.dart`

- [ ] **Step 1: Write failing tests for scan result extraction.**

Expose a small pure helper so scan parsing is testable without a physical camera:

```dart
String? firstScanValue(BarcodeCapture capture) {
  for (final barcode in capture.barcodes) {
    final value = barcode.rawValue?.trim();
    if (value != null && value.isNotEmpty) return value;
  }
  return null;
}
```

Test a capture containing an empty barcode followed by `P001`, and a capture containing only empty/null values. Also add a widget smoke test that finds `MobileScanner` and the `取消` action.

- [ ] **Step 2: Run the scanner tests and verify the helper is missing.**

Run:

```bash
flutter test test/scanner_page_test.dart
```

Expected: FAIL because `firstScanValue` and `ScannerPage` do not exist.

- [ ] **Step 3: Implement the scanner page with the `mobile_scanner 3.5.7` API.**

Use `MobileScannerController(detectionSpeed: DetectionSpeed.noDuplicates)` and render:

```dart
MobileScanner(
  controller: _controller,
  onDetect: _handleDetection,
  errorBuilder: (context, error, child) => _ScannerError(error: error),
)
```

`_handleDetection` must ignore empty results, guard with a `_completed` flag, stop the controller once, and return the trimmed value with `Navigator.pop(context, value)`. The app bar has a `取消` action. The error builder distinguishes permission denial from generic scanner failure and shows a readable message plus a `返回` action. Dispose the controller on page disposal. The platform plugin requests camera permission when the scanner starts; the Android and iOS declarations from Task 1 satisfy the native requirements.

Add function-level comments for result extraction, detection de-duplication, and controller cleanup.

- [ ] **Step 4: Run the scanner tests and analyzer.**

Run:

```bash
flutter test test/scanner_page_test.dart
flutter analyze
```

Expected: tests pass and analyzer reports no new errors. A physical Android/iOS device is still required to verify the native permission prompt and live camera preview.

- [ ] **Step 5: Commit the scanner page independently.**

```bash
git add lib/scanner_page.dart test/scanner_page_test.dart
git commit -m "feat: add QR scanner page"
```

### Task 4: Replace cell editing with the unified row workflow

**Files:**
- Modify: `lib/spreadsheet_page.dart`
- Modify: `test/spreadsheet_page_test.dart`

- [ ] **Step 1: Add failing tests for row lookup and the new page flow.**

Add a pure helper to `spreadsheet_page.dart`:

```dart
int findDeviceRowIndex(
  List<String> headers,
  List<List<String>> rows,
  String deviceNumber,
) {
  final index = headers.indexOf('设备编号');
  if (index < 0) return -1;
  final target = deviceNumber.trim();
  for (var rowIndex = 0; rowIndex < rows.length; rowIndex++) {
    if (index < rows[rowIndex].length && rows[rowIndex][index].trim() == target) {
      return rowIndex;
    }
  }
  return -1;
}
```

Extend widget tests to assert:

```dart
test('finds a device row by trimmed exact device number', () {
  expect(findDeviceRowIndex(
    ['设备编号', '设备名称'],
    [[' P001 ', '设备A'], ['P002', '设备B']],
    ' P001 ',
  ), 0);
  expect(findDeviceRowIndex(
    ['设备编号', '设备名称'],
    [['P001', '设备A']],
    'P003',
  ), -1);
});
```

Update the existing add/edit tests so tapping `新增一行` opens `DeviceEditPage` without changing `共 1 条数据`, and saving the new form changes the count to `共 2 条数据`. Add the same flow for an existing row, asserting the old row is replaced only after the external save callback succeeds. Add a failing-save case asserting the editor remains visible and the list count/data remain unchanged. Add a test that the page displays `未找到设备编号：P999` when a scan callback returns an unknown value. The scanner route test may invoke the `MobileScanner.onDetect` callback from the rendered widget with `BarcodeCapture(barcodes: [Barcode(rawValue: 'P001')])`; no native camera is required for this callback-level test.

- [ ] **Step 2: Run the spreadsheet tests and verify the new assertions fail.**

Run:

```bash
flutter test test/spreadsheet_page_test.dart
```

Expected: existing legacy tests may pass, while the new tests fail because the toolbar, row editor, lookup helper, and scanner route are not implemented.

- [ ] **Step 3: Add row lookup and editor/scanner routes.**

Import `device_edit_page.dart` and `scanner_page.dart`. Replace `_addRow` with an async method that opens `DeviceEditPage` using an all-empty row and `isNew: true`. Add a QR toolbar `IconButton` with tooltip `扫码二维码`; it pushes `ScannerPage`, checks the returned code, uses `findDeviceRowIndex`, and opens the matched row with `isNew: false`. If `设备编号` is absent, show `表格中没有设备编号列`; if no row matches, show `未找到设备编号：<code>`.

Use one private method for opening any editor. Its save callback creates a candidate copy of `_rows`, replaces the target index or appends the new row, awaits `widget.onSave(XlsTable(headers: copy of _headers, rows: candidate))`, and only after success copies the candidate into `_rows`, shows `已保存，等待电脑接收`, and lets `DeviceEditPage` pop. On failure, do not mutate `_rows`; rethrow so `DeviceEditPage` alone shows `保存失败: <error>` and keeps the form open. Guard all async completion points with `mounted`.

- [ ] **Step 4: Remove the obsolete cell dialog and make table row taps open the editor.**

Delete `_editCell`, `_editCellTitle`, `_EditCellDialog`, and `_EditCellDialogState`. Change every `DataCell.onTap` to open the containing row editor. Keep long-press deletion unchanged. Keep the existing top-level save button for compatibility with whole-table edits that are not made through the new editor.

- [ ] **Step 5: Run focused spreadsheet tests and then the full suite.**

Run:

```bash
flutter test test/spreadsheet_page_test.dart
flutter test
```

Expected: all focused and full tests pass; new-row data appears only after successful editor save, scanned rows open with all fields, unknown codes only show a toast, and failed external saves do not mutate the list.

- [ ] **Step 6: Commit the spreadsheet integration.**

```bash
git add lib/spreadsheet_page.dart test/spreadsheet_page_test.dart
git commit -m "feat: connect QR scanning to spreadsheet row editing"
```

### Task 5: Final verification and native build checks

**Files:**
- No additional production files.

- [ ] **Step 1: Review only the task diff and whitespace.**

Run:

```bash
git diff HEAD~4 --check
git diff HEAD~4 --stat
```

Expected: no whitespace errors; the diff contains scanner/edit pages, spreadsheet integration, tests, dependency, and camera declarations, while unrelated existing QR export changes remain outside the task commits.

- [ ] **Step 2: Run static analysis and all tests.**

Run:

```bash
flutter analyze
flutter test
```

Expected: both commands exit successfully with no analyzer errors and all tests passing.

- [ ] **Step 3: Build Android debug when the local toolchain is available.**

Run:

```bash
flutter build apk --debug
```

Expected: the build succeeds and the generated manifest contains camera permission. If the local Android SDK/toolchain is unavailable, report that limitation while retaining analyzer/test results.

- [ ] **Step 4: Perform a device smoke test for the camera permission flow.**

On an Android or iOS device, open a received spreadsheet, tap `扫码二维码`, accept the camera permission, scan a known device code, verify the matching row opens with all fields, edit a non-code field, save, and confirm the external download receives the updated list. Repeat with an unknown code and with a denied permission to verify the two error paths.
