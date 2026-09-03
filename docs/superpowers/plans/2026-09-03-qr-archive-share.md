# 二维码导出包分享 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在二维码导出页通过 `share_plus` 将现有的 `二维码合计.zip` 打开系统分享面板，分享到其他 App。

**Architecture:** `ExportPage` 继续持有二维码 ZIP 的 `Uint8List` 和文件名，新增分享按钮与分享处理中状态。生产路径使用 `XFile.fromData` 和 `Share.shareXFiles`，业务层不显式管理临时文件；测试路径通过可选回调注入，避免 Widget 测试依赖原生分享插件。

**Tech Stack:** Flutter, Dart, `share_plus` 6.3.4, `flutter_test`。

---

## 文件职责

- Modify: `/Users/pengfeiguo/Desktop/Test/excel_app/lib/export_page.dart`：增加分享回调、`share_plus` 默认实现、分享按钮和页面状态反馈。
- Modify: `/Users/pengfeiguo/Desktop/Test/excel_app/test/export_page_test.dart`：验证分享入口、ZIP 数据传递和异常状态。
- No change: `pubspec.yaml`：项目已声明 `share_plus`，不新增依赖。

### Task 1: 为分享行为写失败测试

**Files:**
- Modify: `/Users/pengfeiguo/Desktop/Test/excel_app/test/export_page_test.dart`

- [ ] **Step 1: 添加分享回调测试**

在现有 `main()` 中追加以下两个 Widget 测试。第一个测试要求页面提供 `onShare` 参数、分享按钮和成功状态；第二个测试要求分享异常可见。

```dart
  testWidgets('shares the QR archive through the configured callback',
      (tester) async {
    final controller = _TrackingHomePageController();
    addTearDown(controller.dispose);
    final archive = Uint8List.fromList(<int>[0x50, 0x4B]);
    Uint8List? sharedArchive;
    String? sharedFilename;

    await tester.pumpWidget(
      MaterialApp(
        home: ExportPage(
          controller: controller,
          archive: archive,
          filename: '二维码合计.zip',
          onShare: (bytes, filename) async {
            sharedArchive = bytes;
            sharedFilename = filename;
          },
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('share-qr-archive')), findsOneWidget);

    await tester.tap(find.byKey(const Key('share-qr-archive')));
    await tester.pumpAndSettle();

    expect(sharedArchive, same(archive));
    expect(sharedFilename, '二维码合计.zip');
    expect(find.text('已分享 二维码合计.zip'), findsOneWidget);
  });

  testWidgets('shows an error when sharing the QR archive fails',
      (tester) async {
    final controller = _TrackingHomePageController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: ExportPage(
          controller: controller,
          archive: Uint8List.fromList(<int>[0x50, 0x4B]),
          filename: '二维码合计.zip',
          onShare: (_, __) async {
            throw StateError('share unavailable');
          },
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('share-qr-archive')));
    await tester.pumpAndSettle();

    expect(find.textContaining('分享失败: Bad state: share unavailable'),
        findsOneWidget);
  });
```

- [ ] **Step 2: 运行新增测试确认它因功能缺失而失败**

Run:

```bash
flutter test test/export_page_test.dart
```

Expected: FAIL because `ExportPage` currently has no `onShare` parameter or `share-qr-archive` button. Existing unrelated export-page tests should continue to run.

### Task 2: 实现二维码 ZIP 分享

**Files:**
- Modify: `/Users/pengfeiguo/Desktop/Test/excel_app/lib/export_page.dart`

- [ ] **Step 1: 增加依赖导入和测试回调类型**

在 `export_page.dart` 的导入区域增加 `share_plus`，并在 `ExportPage` 前声明回调类型；在 Widget 中增加可选字段和构造参数：

```dart
import 'package:share_plus/share_plus.dart';

/// 将二维码 ZIP 交给系统分享面板或测试替身。
typedef QrArchiveShareCallback = Future<void> Function(
  Uint8List archive,
  String filename,
);

class ExportPage extends StatefulWidget {
  final HomePageController controller;
  final Uint8List archive;
  final String filename;
  final QrArchiveShareCallback? onShare;

  const ExportPage({
    super.key,
    required this.controller,
    required this.archive,
    required this.filename,
    this.onShare,
  });
```

- [ ] **Step 2: 增加分享状态和处理函数**

在 `_ExportPageState` 增加 `_sharing` 字段，并添加以下函数。传入 `onShare` 时用于测试和可替换调用；未传入时直接使用 `share_plus`。通过分享按钮的 `GlobalKey` 获取定位矩形，兼容 iPad 分享面板。

```dart
  bool _sharing = false;
  final _shareButtonKey = GlobalKey();

  /// 使用 share_plus 分享当前二维码 ZIP，并反馈分享结果。
  Future<void> _shareQrArchive() async {
    if (_starting || _exporting || _sharing) return;
    setState(() {
      _sharing = true;
      _notice = null;
    });
    try {
      final onShare = widget.onShare;
      if (onShare != null) {
        await onShare(widget.archive, widget.filename);
      } else {
        final renderBox =
            _shareButtonKey.currentContext?.findRenderObject() as RenderBox?;
        await Share.shareXFiles(
          <XFile>[
            XFile.fromData(
              widget.archive,
              name: widget.filename,
              mimeType: 'application/zip',
            ),
          ],
          subject: '二维码导出',
          sharePositionOrigin: renderBox == null
              ? null
              : renderBox.localToGlobal(Offset.zero) & renderBox.size,
        );
      }
      if (mounted) setState(() => _notice = '已分享 ${widget.filename}');
    } catch (error) {
      if (mounted) setState(() => _notice = '分享失败: $error');
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }
```

- [ ] **Step 3: 将两个操作按钮并列并绑定状态**

将 `extraAction` 中现有的单个 `FilledButton.icon` 替换为以下按钮区域。保留 `export-qr-archive` 的 Key 和原有导出处理，只在分享时禁用两个操作，避免同时发起操作；分享按钮使用独立 Key 供测试和定位。

```dart
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    key: const Key('export-qr-archive'),
                    onPressed: _starting || _exporting || _sharing
                        ? null
                        : _exportQrArchive,
                    icon: _starting || _exporting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.file_upload_outlined),
                    label: Text(_starting
                        ? '启动服务中...'
                        : (_exporting ? '处理中...' : '导出二维码')),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    key: _shareButtonKey,
                    onPressed: _starting || _exporting || _sharing
                        ? null
                        : _shareQrArchive,
                    icon: _sharing
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.share_outlined),
                    label: Text(_sharing ? '分享中...' : '分享'),
                  ),
                ),
              ],
            ),
```

- [ ] **Step 4: 格式化并运行新增测试确认通过**

Run:

```bash
dart format lib/export_page.dart test/export_page_test.dart
flutter test test/export_page_test.dart
```

Expected: formatter reports the two Dart files formatted, and all tests in `test/export_page_test.dart` pass, including the two new share tests.

### Task 3: 完成回归验证

**Files:**
- Read: `/Users/pengfeiguo/Desktop/Test/excel_app/docs/superpowers/specs/2026-09-03-qr-archive-share-design.md`
- Verify: `/Users/pengfeiguo/Desktop/Test/excel_app/lib/export_page.dart`
- Verify: `/Users/pengfeiguo/Desktop/Test/excel_app/test/export_page_test.dart`

- [ ] **Step 1: 运行静态分析**

Run:

```bash
flutter analyze
```

Expected: exit code 0 and no analyzer errors.

- [ ] **Step 2: 运行完整测试集**

Run:

```bash
flutter test
```

Expected: exit code 0 and all tests pass.

- [ ] **Step 3: 检查变更范围**

Run:

```bash
git diff --check
git status --short
```

Expected: `git diff --check` has no output; the intended changes include the design/plan documents and the two implementation/test files, while all pre-existing user changes remain untouched. Do not commit automatically.
