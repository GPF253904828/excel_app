# 在线设备自动加载全部 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为在线设备页增加“自动加载全部”按钮，按接口返回的 `nextStart` 连续加载分页，并在已有数据计数后显示当前加载页状态。

**Architecture:** `OnlinePage` 负责自动分页循环、加载页数、并发保护和请求错误状态，继续复用现有 `_loadPage`。`SpreadsheetPage` 只新增一个可选状态文本参数，将它拼接到既有 AppBar 数据计数中；现有下拉刷新和触底加载接口保持不变。

**Tech Stack:** Flutter, Dart, `flutter_test`。

---

## 文件职责

- Modify: `/Users/pengfeiguo/Desktop/Test/excel_app/lib/online/online_page.dart`：维护自动加载全部状态、连续分页、页码文案和顶部按钮。
- Modify: `/Users/pengfeiguo/Desktop/Test/excel_app/lib/spreadsheet_page.dart`：接收可选分页状态并显示在 AppBar 计数后。
- Modify: `/Users/pengfeiguo/Desktop/Test/excel_app/test/online_page_test.dart`：验证默认首屏、自动分页、状态文案、完成和失败行为。
- No change: `pubspec.yaml`：不新增依赖。

### Task 1: 为自动加载流程写失败测试

**Files:**
- Modify: `/Users/pengfeiguo/Desktop/Test/excel_app/test/online_page_test.dart`

- [x] **Step 1: 更新首次加载状态断言**

将现有测试 `刷新首页时显示 Loading` 改名为 `刷新首页时显示第一页加载状态`，并将等待中的断言改为：

```dart
    expect(find.text('正在加载第一页'), findsOneWidget);
```

这会把已确认的用户可见状态写入回归测试。

- [x] **Step 2: 添加自动分页成功测试**

在现有分页测试后追加以下 Widget 测试。第一页返回 50 条并声明下一页从 50 开始；第二页暂不完成，用于确认 AppBar 在请求期间显示当前页状态。

```dart
  testWidgets('点击自动加载全部后按 nextStart 连续加载并显示状态',
      (tester) async {
    final requestedStarts = <int>[];
    final secondPage = Completer<DeviceListResult>();

    await _pumpWidget(
      tester,
      _app(
        onList: ({required start, required limit}) {
          requestedStarts.add(start);
          if (start == 0) {
            return Future<DeviceListResult>.value(
              _listResult(
                _deviceRows('P', 50),
                total: 120,
                start: 0,
                limit: limit,
                hasMore: true,
                nextStart: 50,
              ),
            );
          }
          return secondPage.future;
        },
      ),
    );
    await tester.pumpAndSettle();

    expect(requestedStarts, <int>[0]);
    expect(find.byTooltip('自动加载全部'), findsOneWidget);
    expect(find.text('已加载50/120条数据'), findsOneWidget);

    await tester.tap(find.byTooltip('自动加载全部'));
    await tester.pump();

    expect(requestedStarts, <int>[0, 50]);
    expect(
      find.text('已加载50/120条数据，正在加载第2页'),
      findsOneWidget,
    );

    secondPage.complete(
      _listResult(
        _deviceRows('P', 70, offset: 50),
        total: 120,
        start: 50,
        limit: 70,
      ),
    );
    await tester.pumpAndSettle();

    expect(requestedStarts, <int>[0, 50]);
    expect(find.text('已全部加载完成120条数据'), findsOneWidget);
  });
```

- [x] **Step 3: 添加自动分页失败测试**

追加以下测试，确认第二页失败后不会继续请求第三页，且已加载数据和失败状态仍然可见：

```dart
  testWidgets('自动加载分页失败后停止并保留已加载数据', (tester) async {
    final requestedStarts = <int>[];

    await _pumpWidget(
      tester,
      _app(
        onList: ({required start, required limit}) async {
          requestedStarts.add(start);
          if (start == 0) {
            return _listResult(
              _deviceRows('P', 50),
              total: 120,
              start: 0,
              limit: limit,
              hasMore: true,
              nextStart: 50,
            );
          }
          throw DeviceApiException('第二页加载失败');
        },
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('自动加载全部'));
    await tester.pumpAndSettle();

    expect(requestedStarts, <int>[0, 50]);
    expect(find.text('P000'), findsOneWidget);
    expect(find.textContaining('加载失败: 第二页加载失败'), findsOneWidget);
  });
```

- [x] **Step 4: 运行测试确认 RED**

Run:

```bash
flutter test test/online_page_test.dart
```

Expected: FAIL because `OnlinePage` currently has no `自动加载全部` action or pagination status parameter, and the refresh loading page still displays `Loading...`.

### Task 2: 实现自动分页和状态展示

**Files:**
- Modify: `/Users/pengfeiguo/Desktop/Test/excel_app/lib/online/online_page.dart`
- Modify: `/Users/pengfeiguo/Desktop/Test/excel_app/lib/spreadsheet_page.dart`

- [x] **Step 1: 增加在线页自动加载状态字段**

在 `_OnlinePageState` 的分页字段中增加以下状态：

```dart
  bool _loadingAll = false;
  int _loadedPageCount = 0;
  String? _paginationStatus = '正在加载第一页';
```

在 `_resetRows()` 中将 `_loadedPageCount` 重置为 `0`，确保刷新或切换配置后下一页重新从第二页计数。

- [x] **Step 2: 为首屏加载设置状态并追踪已加载页数**

将 `_loadFirstPage()` 改为以下实现；请求结束后清除临时状态，失败仍由 `_loadPage` 写入现有错误状态：

```dart
  /// 清空当前数据并加载分页列表的首页，同时显示第一页状态。
  Future<void> _loadFirstPage() async {
    if (mounted) setState(() => _paginationStatus = '正在加载第一页');
    try {
      await _loadPage(start: 0, replace: true);
    } finally {
      if (mounted) setState(() => _paginationStatus = null);
    }
  }
```

在 `_loadPage()` 成功更新列表的 `setState` 中加入：

```dart
          _loadedPageCount = replace ? 1 : _loadedPageCount + 1;
```

- [x] **Step 3: 增加自动加载全部循环**

在 `_loadMore()` 后增加下面的方法。它顺序使用 `_nextStart`，检测重复起始位置避免异常接口导致无限循环；分页失败时保留已加载数据并保留错误状态，按钮恢复为可重试状态。

```dart
  /// 按接口返回的 nextStart 连续加载所有剩余分页。
  Future<void> _loadAll() async {
    if (_loading || _loadingMore || _loadingAll || !_hasMore) return;
    setState(() => _loadingAll = true);
    final requestedStarts = <int>{};
    try {
      while (_hasMore && mounted) {
        final start = _nextStart;
        if (!requestedStarts.add(start)) {
          throw DeviceApiException('分页位置未推进');
        }
        final page = _loadedPageCount + 1;
        setState(() => _paginationStatus = '正在加载第${page}页');
        await _loadPage(start: start, replace: false);
      }
      if (mounted) setState(() => _paginationStatus = null);
    } catch (error) {
      print('[Online][load-all][error] $error');
      if (mounted) {
        setState(() => _paginationStatus = '加载失败: ${_errorText(error)}');
        ToastUtil.showCenter(_errorText(error));
      }
    } finally {
      if (mounted) setState(() => _loadingAll = false);
    }
  }
```

- [x] **Step 4: 增加顶部按钮并锁定并发入口**

在 `_tableActions()` 中刷新按钮前加入以下 `IconButton`。按钮只在存在下一页且无加载任务时可用；刷新和配置按钮的现有 `onPressed` 条件也追加 `_loadingAll`，避免自动加载期间触发其他请求。

```dart
        IconButton(
          key: const Key('online-load-all'),
          onPressed: _loading || _loadingMore || _loadingAll || !_hasMore
              ? null
              : _loadAll,
          tooltip: '自动加载全部',
          icon: const Icon(Icons.download_for_offline_outlined),
        ),
```

同步将配置和刷新按钮的禁用条件从 `_loading || _loadingMore` 扩展为：

```dart
_loading || _loadingMore || _loadingAll
```

- [x] **Step 5: 让首屏和表格页传递状态**

在 `_buildLoadingPage()` 的加载分支中，将原有 `Text('Loading...')` 改为：

```dart
                    Text(_paginationStatus ?? 'Loading...'),
```

在 `SpreadsheetPage` 增加字段和构造参数：

```dart
  final String? paginationStatus;

  const SpreadsheetPage({
    super.key,
    required this.file,
    required this.table,
    this.onSave,
    this.onSaveRow,
    this.onDeleteRow,
    this.onRefresh,
    this.onLoadMore,
    this.hasMore = false,
    this.totalCount,
    this.paginationStatus,
    this.isLoading = false,
    this.readOnly = false,
    this.title,
    this.appBarActions = const <Widget>[],
    this.qrExportPageBuilder,
    this.onViewRow,
    this.onExportQrCodes,
  });
```

在在线页创建 `SpreadsheetPage` 时传入：

```dart
      paginationStatus: _paginationStatus,
      isLoading: _loading || _loadingMore || _loadingAll,
```

在 `SpreadsheetPage._dataCountText()` 中先生成原有计数，再追加可选状态：

```dart
  /// 根据分页状态展示计数和当前加载状态。
  String _dataCountText() {
    final total = widget.totalCount;
    final count = total == null
        ? '共 ${_rows.length} 条数据'
        : !widget.hasMore
            ? '已全部加载完成$total条数据'
            : '已加载${_rows.length}/$total条数据';
    final status = widget.paginationStatus;
    return status == null || status.isEmpty ? count : '$count，$status';
  }
```

- [x] **Step 6: 格式化并运行在线页测试确认 GREEN**

Run:

```bash
dart format lib/online/online_page.dart lib/spreadsheet_page.dart test/online_page_test.dart
flutter test test/online_page_test.dart
```

Expected: all online-page tests pass, including automatic `nextStart` pagination, page status, completion text and failure stop behavior.

### Task 3: 完成回归验证

**Files:**
- Read: `/Users/pengfeiguo/Desktop/Test/excel_app/docs/superpowers/specs/2026-09-03-online-auto-load-design.md`
- Verify: `/Users/pengfeiguo/Desktop/Test/excel_app/lib/online/online_page.dart`
- Verify: `/Users/pengfeiguo/Desktop/Test/excel_app/lib/spreadsheet_page.dart`
- Verify: `/Users/pengfeiguo/Desktop/Test/excel_app/test/online_page_test.dart`

- [x] **Step 1: 运行相关分页和表格测试**

Run:

```bash
flutter test test/online_page_test.dart test/spreadsheet_page_test.dart
```

Expected: exit code 0，且现有触底加载、下拉刷新、编辑和只读列表测试继续通过。

- [x] **Step 2: 运行静态分析**

Run:

```bash
flutter analyze
```

Expected: exit code 0 and no analyzer errors.

- [x] **Step 3: 运行完整测试集**

Run:

```bash
flutter test
```

Expected: exit code 0 and all tests pass.

- [x] **Step 4: 检查差异和工作区**

Run:

```bash
git diff --check
git status --short
```

Expected: `git diff --check` has no output; only the planned source/test/docs changes are present, existing user changes are preserved, and no commit is created automatically.
