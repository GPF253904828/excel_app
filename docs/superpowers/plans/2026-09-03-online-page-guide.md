# 在线设备页操作引导 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** 在在线设备页前三次进入时显示一个 Overlay，引导用户认识“加载全部”“刷新”“接口配置”三个顶部按钮。

**Architecture:** `OnlinePage` 负责记录引导展示次数、获取三个按钮的全局位置和打开模态引导层。页面级 Overlay 容器托管底层页面和引导 entry，引导层在同一个全屏 Overlay 中以三列文字卡片配合箭头指向三个按钮，使用 Flutter 原生 `OverlayEntry`、`ModalBarrier` 和 `CustomPainter`，不新增第三方引导库。现有业务按钮通过 `KeyedSubtree` 保留测试 Key，同时由 `GlobalKey` 提供定位。

**Tech Stack:** Flutter, Dart, `shared_preferences`, `flutter_test`。

---

## 文件职责

- Modify: `/Users/pengfeiguo/Desktop/Test/excel_app/lib/online/online_page.dart`：增加引导次数、按钮定位、Overlay 引导视图和按钮顺序调整。
- Modify: `/Users/pengfeiguo/Desktop/Test/excel_app/test/online_page_test.dart`：关闭现有测试中的生产引导，并增加三次展示、第四次隐藏、文案和关闭测试。
- Create: `/Users/pengfeiguo/Desktop/Test/excel_app/docs/superpowers/specs/2026-09-03-online-page-guide-design.md`：记录已确认的交互设计。
- No change: `pubspec.yaml`：项目已经依赖 `shared_preferences`，不新增依赖。

### Task 1: 为 Overlay 引导写失败测试

**Files:**
- Modify: `/Users/pengfeiguo/Desktop/Test/excel_app/test/online_page_test.dart`

- [x] **Step 1: 给测试页面增加引导开关参数**

在 `_app` 测试辅助方法参数中加入 `showOnboardingGuide = false`，并把它传给 `OnlinePage`。默认关闭，避免已有分页、编辑和配置测试被模态 Overlay 阻塞；专门的引导测试显式开启。

```dart
Widget _app({
  DeviceListCallback? onList,
  Future<DeviceResult> Function(String, Map<String, dynamic>)? onModify,
  Future<DeviceResult> Function(Map<String, dynamic>)? onAdd,
  Future<DeviceResult> Function(String)? onDelete,
  OnlineConfigStore configStore = const OnlineConfigStore(),
  bool readOnly = false,
  QrExportPageBuilder? qrExportPageBuilder,
  bool showOnboardingGuide = false,
}) {
  return MaterialApp(
    home: OnlinePage(
      onList: onList,
      onModify: onModify,
      onAdd: onAdd,
      onDelete: onDelete,
      configStore: configStore,
      readOnly: readOnly,
      qrExportPageBuilder: qrExportPageBuilder,
      showOnboardingGuide: showOnboardingGuide,
    ),
  );
}
```

- [x] **Step 2: 添加前三次显示、第四次隐藏测试**

在 `main()` 的在线列表 Widget 测试区域追加以下测试。它检查一个 Overlay 同时包含三个说明、关闭按钮可以移除 Overlay，并验证第四次进入不再出现。

```dart
  testWidgets('前三次进入显示三个顶部按钮的操作引导', (tester) async {
    Future<DeviceListResult> list({required int start, required int limit}) =>
        Future<DeviceListResult>.value(
          _listResult(
            <Map<String, dynamic>>[
              _deviceRow(deviceNo: 'P001', name: '设备A'),
            ],
            total: 1,
            start: start,
            limit: limit,
          ),
        );

    for (var entry = 0; entry < 3; entry++) {
      await tester.pumpWidget(
        _app(onList: list, showOnboardingGuide: true),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('online-page-guide')), findsOneWidget);
      expect(find.text('加载全部'), findsOneWidget);
      expect(find.text('自动加载所有分页，不用再上拉加载更多。'), findsOneWidget);
      expect(find.text('刷新'), findsOneWidget);
      expect(find.text('清空当前列表，重新加载第一页。'), findsOneWidget);
      expect(find.text('接口配置'), findsOneWidget);
      expect(find.text('切换在线设备接口配置。'), findsOneWidget);
      expect(find.byKey(const Key('online-page-guide-dismiss')), findsOneWidget);

      await tester.tap(find.byKey(const Key('online-page-guide-dismiss')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('online-page-guide')), findsNothing);
    }

    await tester.pumpWidget(_app(onList: list, showOnboardingGuide: true));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('online-page-guide')), findsNothing);
  });

  testWidgets('只读在线设备页不显示三按钮操作引导', (tester) async {
    await _pumpWidget(
      tester,
      _app(
        readOnly: true,
        showOnboardingGuide: true,
        onList: ({required start, required limit}) async => _listResult(
          <Map<String, dynamic>>[
            _deviceRow(deviceNo: 'P001', name: '设备A'),
          ],
          total: 1,
          start: start,
          limit: limit,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('online-page-guide')), findsNothing);
  });
```

- [x] **Step 3: 运行测试确认 RED**

Run:

```bash
flutter test test/online_page_test.dart
```

Expected: FAIL at compile time because `OnlinePage` currently没有 `showOnboardingGuide` 参数；修复参数后，在引导行为尚未实现时应找不到 `online-page-guide`。

### Task 2: 实现前三次 Overlay 引导

**Files:**
- Modify: `/Users/pengfeiguo/Desktop/Test/excel_app/lib/online/online_page.dart`

- [x] **Step 1: 增加引导配置、按钮定位 Key 和 Widget 参数**

导入 `dart:math` 和 `shared_preferences`，在 `OnlinePage` 增加生产默认开启的开关和三个按钮定位 Key：

```dart
import 'dart:math' as math;

import 'package:shared_preferences/shared_preferences.dart';

class OnlinePage extends StatefulWidget {
  final bool showOnboardingGuide;
  final DeviceListCallback? onList;
  final DeviceModifyCallback? onModify;
  final DeviceAddCallback? onAdd;
  final DeviceDeleteCallback? onDelete;
  final QrExportPageBuilder? qrExportPageBuilder;
  final OnlineConfigStore configStore;
  final bool readOnly;

  const OnlinePage({
    super.key,
    this.showOnboardingGuide = true,
    this.onList,
    this.onModify,
    this.onAdd,
    this.onDelete,
    this.qrExportPageBuilder,
    this.configStore = const OnlineConfigStore(),
    this.readOnly = false,
  });
```

在 `_OnlinePageState` 增加：

```dart
  static const _guideSeenCountKey = 'online_page_guide_seen_count';
  static const _guideMaxDisplays = 3;

  final _loadAllButtonKey = GlobalKey();
  final _refreshButtonKey = GlobalKey();
  final _configButtonKey = GlobalKey();
  bool _guideCheckScheduled = false;
```

- [x] **Step 2: 在首次列表加载后检查展示次数**

在 `_initialize()` 成功完成 `_loadFirstPage()` 后调用 `_showOnboardingGuideIfNeeded()`。实现必须在偏好设置异常时静默跳过，并且先写入次数再安排 Overlay，避免 rebuild 重复计数：

```dart
  /// 首次列表加载完成后，按本地次数决定是否显示操作引导。
  Future<void> _showOnboardingGuideIfNeeded() async {
    if (!widget.showOnboardingGuide ||
        widget.readOnly ||
        _guideCheckScheduled ||
        !mounted) {
      return;
    }
    _guideCheckScheduled = true;
    try {
      final preferences = await SharedPreferences.getInstance();
      final seen = preferences.getInt(_guideSeenCountKey) ?? 0;
      if (seen >= _guideMaxDisplays || !mounted) return;
      await preferences.setInt(_guideSeenCountKey, seen + 1);
      if (!mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _presentOnboardingGuide();
      });
    } catch (error) {
      print('[Online][guide][error] $error');
    }
  }
```

- [x] **Step 3: 获取按钮矩形并打开原生 Overlay**

增加按钮位置转换和 Overlay 打开方法。三个矩形顺序必须与工具栏顺序一致；任一按钮尚未布局时跳过本次显示，不影响主页面：

```dart
  /// 将按钮的 RenderBox 坐标转换为 Overlay 使用的全局矩形。
  Rect? _globalRect(GlobalKey key) {
    final renderObject = key.currentContext?.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) return null;
    return renderObject.localToGlobal(Offset.zero) & renderObject.size;
  }

  /// 打开指向顶部三个操作按钮的模态引导层。
  void _presentOnboardingGuide() {
    final targets = <Rect?>[
      _globalRect(_loadAllButtonKey),
      _globalRect(_refreshButtonKey),
      _globalRect(_configButtonKey),
    ];
    if (targets.any((target) => target == null)) return;
    _guideHostKey.currentState?.showGuide(targets.cast<Rect>());
  }
```

- [x] **Step 4: 调整工具栏按钮顺序并接入 GlobalKey**

将 `_tableActions()` 顺序调整为加载全部、刷新、接口配置。每个 `IconButton` 外包 `KeyedSubtree`：外层使用定位 `GlobalKey`，内层保留现有测试 Key。保留现有禁用条件和按钮回调。

```dart
  /// 创建在线表格使用的统一工具栏操作。
  List<Widget> _tableActions() => <Widget>[
        KeyedSubtree(
          key: _loadAllButtonKey,
          child: IconButton(
            key: const Key('online-load-all'),
            onPressed: _loading || _loadingMore || _loadingAll || !_hasMore
                ? null
                : _loadAll,
            tooltip: '自动加载全部',
            icon: const Icon(Icons.download_for_offline_outlined),
          ),
        ),
        KeyedSubtree(
          key: _refreshButtonKey,
          child: IconButton(
            key: const Key('online-refresh'),
            onPressed:
                _loading || _loadingMore || _loadingAll ? null : _refresh,
            tooltip: '刷新列表',
            icon: const Icon(Icons.refresh),
          ),
        ),
        if (!widget.readOnly)
          KeyedSubtree(
            key: _configButtonKey,
            child: IconButton(
              key: const Key('online-config'),
              onPressed:
                  _loading || _loadingMore || _loadingAll ? null : _openConfig,
              tooltip: '接口配置',
              icon: const Icon(Icons.settings_outlined),
            ),
          ),
      ];
```

- [x] **Step 5: 添加三列说明卡片和箭头 Painter**

在 `online_page.dart` 文件末尾增加 `_OnlinePageOverlayHost`、`_OnlinePageGuide` 和 `_GuideArrowPainter`。`_OnlinePageGuide` 根节点使用 `Key('online-page-guide')`，Stack 第一层放置不可关闭的 `ModalBarrier`，三列从左到右固定对应三个目标矩形，底部提供 `Key('online-page-guide-dismiss')` 的“知道了”按钮；关闭时由 `_OnlinePageOverlayHostState.dismissGuide()` 移除 entry。

实现要求如下：

```dart
/// 展示在线设备页三个顶部操作的单层模态引导。
class _OnlinePageGuide extends StatelessWidget {
  final List<Rect> targets;
  final VoidCallback onDismiss;

  const _OnlinePageGuide({
    required this.targets,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      key: const Key('online-page-guide'),
      color: Colors.transparent,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final cardGap = 8.0;
          final cardWidth = (constraints.maxWidth - 32 - cardGap * 2) / 3;
          final cardTop = math.max(
            96.0,
            targets.map((target) => target.bottom).reduce(math.max) + 24,
          );
          final cardCenters = <Offset>[
            for (var index = 0; index < 3; index++)
              Offset(16 + cardWidth * (index + .5) + cardGap * index, cardTop),
          ];
          return Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(
                  key: const Key('online-page-guide-arrows'),
                  painter: _GuideArrowPainter(
                    targets: targets,
                    starts: cardCenters,
                  ),
                ),
              ),
              Positioned(
                top: cardTop,
                left: 16,
                right: 16,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _card(
                      title: '加载全部',
                      description: '自动加载所有分页，不用再上拉加载更多。',
                      width: cardWidth,
                    ),
                    SizedBox(width: cardGap),
                    _card(
                      title: '刷新',
                      description: '清空当前列表，重新加载第一页。',
                      width: cardWidth,
                    ),
                    SizedBox(width: cardGap),
                    _card(
                      title: '接口配置',
                      description: '切换在线设备接口配置。',
                      width: cardWidth,
                    ),
                  ],
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 24,
                child: SafeArea(
                  top: false,
                  child: Center(
                    child: FilledButton(
                      key: const Key('online-page-guide-dismiss'),
                      onPressed: onDismiss,
                      child: const Text('知道了'),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// 构建单个操作说明卡片，统一三列的尺寸和文字样式。
  Widget _card({
    required String title,
    required String description,
    required double width,
  }) => SizedBox(
        width: width,
        child: Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.black87,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  description,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.black87,
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}

/// 在说明卡片和目标按钮之间绘制带箭头的引导线。
class _GuideArrowPainter extends CustomPainter {
  final List<Rect> targets;
  final List<Offset> starts;

  const _GuideArrowPainter({
    required this.targets,
    required this.starts,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;
    for (var index = 0; index < targets.length; index++) {
      final start = starts[index];
      final end = Offset(targets[index].center.dx, targets[index].bottom + 4);
      canvas.drawLine(start, end, linePaint);
      final direction = (end - start) / (end - start).distance;
      final side = Offset(-direction.dy, direction.dx);
      final base = end - direction * 12;
      canvas.drawLine(end, base + side * 5, linePaint);
      canvas.drawLine(end, base - side * 5, linePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _GuideArrowPainter oldDelegate) =>
      oldDelegate.targets != targets || oldDelegate.starts != starts;
}
```

- [x] **Step 6: 格式化并运行引导测试确认 GREEN**

Run:

```bash
dart format lib/online/online_page.dart test/online_page_test.dart
flutter test test/online_page_test.dart
```

Expected: 在线页全部测试通过；前三次进入显示一个包含三段说明和箭头的 Overlay，关闭后可继续操作，第四次进入不显示。

### Task 3: 完成回归验证

**Files:**
- Read: `/Users/pengfeiguo/Desktop/Test/excel_app/docs/superpowers/specs/2026-09-03-online-page-guide-design.md`
- Verify: `/Users/pengfeiguo/Desktop/Test/excel_app/lib/online/online_page.dart`
- Verify: `/Users/pengfeiguo/Desktop/Test/excel_app/test/online_page_test.dart`

- [x] **Step 1: 运行相关测试**

Run:

```bash
flutter test test/online_page_test.dart test/spreadsheet_page_test.dart test/export_page_test.dart test/qr_create_page_test.dart
```

Expected: 与本次功能相关的测试全部通过。

- [x] **Step 2: 运行静态分析**

Run:

```bash
flutter analyze
```

Expected: 无本次新增 analyzer error；若存在工作区原有 warning，单独记录。

- [x] **Step 3: 运行完整测试集**

Run:

```bash
flutter test
```

Expected: 无本次新增失败；工作区原有失败单独记录。

- [x] **Step 4: 检查差异和工作区**

Run:

```bash
git diff --check
git status --short
```

Expected: `git diff --check` 无输出，现有用户改动保留，不自动创建提交。
