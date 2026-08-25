# 二维码生成与导出 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在表格编辑页打开二维码页，选择设备后使用 `qr_flutter` 生成 PNG，压缩为 `A.zip` 并沿用现有文件服务导出到电脑。

**Architecture:** `QrCreatePage` 只管理设备选择、操作按钮和状态；`QrCodeService` 负责设备记录提取、文件名清理、`qr_flutter` 二维码绘制、PNG 文件写入和 ZIP 打包；`HomePageController` 将 ZIP 交给现有 `FileServer`。`SpreadsheetPage` 只负责把当前编辑中的数据和导出回调传给新页面。

**Tech Stack:** Flutter/Dart 2.19、`qr_flutter` 4.1.0、`archive` 3.x、`dart:ui`、现有 `path_provider` 和 `FileServer`。

---

### Task 1: Add QR generation service and dependency

**Files:**
- Modify: `/Users/pengfeiguo/Desktop/Test/excel_app/pubspec.yaml`
- Create: `/Users/pengfeiguo/Desktop/Test/excel_app/lib/qr_code_service.dart`
- Test: `/Users/pengfeiguo/Desktop/Test/excel_app/test/qr_code_service_test.dart`

- [ ] **Step 1: Add the ZIP dependency without changing the existing `qr_flutter` dependency.**

Add this direct dependency beside `qr_flutter`:

```yaml
  archive: ^3.3.7
```

- [ ] **Step 2: Write failing tests for device extraction and naming.**

Add tests for the public helpers:

```dart
test('extracts only rows with both device fields', () {
  final devices = extractQrDevices(
    ['设备编号', '设备名称', '型号'],
    [
      [' P001 ', '设备A', 'A'],
      ['P002', '', 'B'],
      ['', '设备C', 'C'],
    ],
  );

  expect(devices, [const QrDevice('P001', '设备A')]);
});

test('sanitizes names and adds a suffix for duplicates', () {
  final used = <String>{};
  expect(qrFileName(const QrDevice('A/B', '设备:C'), used), 'A_B设备_C.png');
  expect(qrFileName(const QrDevice('A/B', '设备:C'), used), 'A_B设备_C_2.png');
});
```

- [ ] **Step 3: Run the focused test and confirm it fails for missing symbols.**

Run: `flutter test test/qr_code_service_test.dart`

Expected: FAIL because `QrDevice`, `extractQrDevices`, and `qrFileName` are not implemented yet.

- [ ] **Step 4: Implement the service data helpers and PNG/ZIP operations.**

Define the following public API in `lib/qr_code_service.dart`:

```dart
class QrDevice {
  final String deviceNumber;
  final String deviceName;

  const QrDevice(this.deviceNumber, this.deviceName);
}

List<QrDevice> extractQrDevices(
  List<String> headers,
  List<List<String>> rows,
);

String qrFileName(QrDevice device, Set<String> usedNames);

class QrCodeService {
  final Directory outputDirectory;

  const QrCodeService(this.outputDirectory);

  Future<List<File>> generate(List<QrDevice> devices);
  Future<Uint8List> zip(List<File> files);
}
```

`generate` must remove old `.png` files from `outputDirectory`, create one PNG per input device, and use `QrPainter(data: device.deviceNumber, version: QrVersions.auto)` from `qr_flutter`. Paint a white `640x240` canvas with the QR on the left and two `TextPainter` labels on the right, then encode with `ImageByteFormat.png`. `zip` must add every generated file to an `Archive` and return `ZipEncoder().encode(archive)` as `Uint8List`.

- [ ] **Step 5: Run the focused tests and add PNG/ZIP assertions.**

Run: `flutter pub get && flutter test test/qr_code_service_test.dart`

Expected: helper, PNG existence, `.png` suffix, and ZIP entry tests PASS.

- [ ] **Step 6: Commit the service independently.**

Run:

```bash
git add pubspec.yaml pubspec.lock lib/qr_code_service.dart test/qr_code_service_test.dart
git commit -m "feat: add QR code image generation service"
```

### Task 2: Add selectable QR creation page

**Files:**
- Create: `/Users/pengfeiguo/Desktop/Test/excel_app/lib/qr_create_page.dart`
- Test: `/Users/pengfeiguo/Desktop/Test/excel_app/test/qr_create_page_test.dart`

- [ ] **Step 1: Write failing widget tests for default selection and selection controls.**

Build `QrCreatePage` with one valid device and assert the row checkbox starts checked, the top checkbox is checked, tapping the row unchecks both, and tapping the top checkbox selects all again. Also assert that tapping “生成” with no selected rows displays `请至少选择一条设备数据`.

- [ ] **Step 2: Run the page test and confirm it fails before the page exists.**

Run: `flutter test test/qr_create_page_test.dart`

Expected: FAIL because `QrCreatePage` is not defined.

- [ ] **Step 3: Implement the page state and controls.**

The constructor must accept `headers`, `rows`, an optional `QrCodeService`, and `Future<void> Function(Uint8List bytes, String filename)? onExport`. Initialize every valid device as selected. Render a header checkbox with `value: true`, `false`, or `null` based on selection, one checkbox per device, and buttons with tooltips/text `生成` and `导出`.

Implement these state transitions:

```dart
void _changeSelection(int index, bool selected) {
  setState(() {
    _selected[index] = selected;
    _generatedFiles = null;
    _status = '请选择设备后重新生成';
  });
}

Future<void> _generate() async {
  final selected = _selectedDevices;
  if (selected.isEmpty) {
    setState(() => _status = '请至少选择一条设备数据');
    return;
  }
  setState(() => _status = '生成中');
  final files = await _service.generate(selected);
  if (!mounted) return;
  setState(() {
    _generatedFiles = files;
    _status = '生成已完成';
  });
}
```

Wrap generation and export in `try/catch/finally` so failures show `失败: $error`, and disable buttons while `_busy` is true. Export must set `压缩中`, create `A.zip` from the last generated files, set `导出中`, call `onExport`, then set `导出已完成`.

- [ ] **Step 4: Run page tests and confirm selection/status behavior passes.**

Run: `flutter test test/qr_create_page_test.dart`

Expected: PASS for default selection, single selection, select-all, empty selection validation, and generation status.

- [ ] **Step 5: Commit the page independently.**

Run:

```bash
git add lib/qr_create_page.dart test/qr_create_page_test.dart
git commit -m "feat: add selectable QR creation page"
```

### Task 3: Connect the page to spreadsheet and computer export

**Files:**
- Modify: `/Users/pengfeiguo/Desktop/Test/excel_app/lib/spreadsheet_page.dart`
- Modify: `/Users/pengfeiguo/Desktop/Test/excel_app/lib/home_page.dart`
- Modify: `/Users/pengfeiguo/Desktop/Test/excel_app/lib/home_page_controller.dart`
- Modify: `/Users/pengfeiguo/Desktop/Test/excel_app/lib/network_tools/file_service.dart`
- Modify: `/Users/pengfeiguo/Desktop/Test/excel_app/test/spreadsheet_page_test.dart`
- Modify: `/Users/pengfeiguo/Desktop/Test/excel_app/test/file_service_test.dart`

- [ ] **Step 1: Write failing integration/widget assertions.**

Assert that `SpreadsheetPage` renders a QR button, tapping it opens `QrCreatePage` with the current device data, and the export callback is wired. Extend the file service test to assert a queued ZIP response uses `application/zip` and `A.zip`.

- [ ] **Step 2: Run the focused integration tests and confirm the new assertions fail.**

Run: `flutter test test/spreadsheet_page_test.dart test/file_service_test.dart`

Expected: FAIL because the QR button, callback, and ZIP content type are not wired yet.

- [ ] **Step 3: Add the spreadsheet route and controller callback.**

Add an optional `onExportQrCodes` callback to `SpreadsheetPage`, add a QR toolbar button that pushes `QrCreatePage(headers: _headers, rows: _rows, onExport: widget.onExportQrCodes)`, and pass `(bytes, filename) => _controller.exportQrArchive(bytes, filename)` from `HomePage`.

Add `HomePageController.exportQrArchive(Uint8List bytes, String filename)` that throws if the file server is not running and queues the bytes with `contentType: 'application/zip'`.

- [ ] **Step 4: Make `FileServer` preserve the queued content type.**

Add `_pendingExportContentType`, accept an optional `contentType` in `queueExport`, set the response header from the pending value, and clear it after the response is consumed. Keep CSV export behavior unchanged by defaulting to `text/csv; charset=utf-8`.

- [ ] **Step 5: Run focused integration tests and then the full test suite.**

Run: `flutter test test/spreadsheet_page_test.dart test/file_service_test.dart && flutter test`

Expected: all tests PASS.

- [ ] **Step 6: Commit the integration changes.**

Run:

```bash
git add lib/spreadsheet_page.dart lib/home_page.dart lib/home_page_controller.dart lib/network_tools/file_service.dart test/spreadsheet_page_test.dart test/file_service_test.dart
git commit -m "feat: connect QR export to spreadsheet flow"
```

### Task 4: Verify the finished feature

**Files:**
- No new production files; inspect the complete diff and test output.

- [ ] **Step 1: Run static analysis.**

Run: `flutter analyze`

Expected: exit code 0 with no analyzer errors.

- [ ] **Step 2: Run the full test suite.**

Run: `flutter test`

Expected: all tests pass.

- [ ] **Step 3: Build the target desktop app when the local Flutter toolchain supports it.**

Run: `flutter build windows --debug`

Expected: exit code 0. If the platform toolchain is unavailable, report that limitation explicitly and retain the successful unit/widget test evidence.

- [ ] **Step 4: Review the final diff for scope and unused imports.**

Run: `git diff HEAD~3 --stat && git diff HEAD~3 --check`

Expected: only QR generation, selection, ZIP export, dependency, tests, and their documentation are changed; `git diff --check` reports no whitespace errors.
