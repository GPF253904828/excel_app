# 首页大厅与本地配置页 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将移动端首页改为“在线/本地”大厅，并把现有文件传输功能迁移到独立的 `LocalPage`。

**Architecture:** `HomePage` 只负责大厅导航，`HomePageView` 只渲染两个入口；`LocalPage` 持有并释放现有 `HomePageController`，通过新的本地视图承接原首页的文件服务、文件管理和表格流程。`OnlinePage`、`HomePageController` 的业务接口和桌面端 `PCHomePage` 保持不变。

**Tech Stack:** Flutter, Dart, `flutter_test`, 现有 `HomePageController`、`SpreadsheetPage`、`OnlinePage`。

---

### Task 1: Update lobby and local view tests

**Files:**
- Modify: `test/home_page_view_test.dart`
- Create: `test/local_page_view_test.dart`

- [ ] **Step 1: Replace the old local-home assertions with lobby assertions**

Update `test/home_page_view_test.dart` so `HomePageView` is constructed with `onOnlinePage` and `onLocalPage`, then assert that it renders exactly the `在线` and `本地` actions and that tapping each action invokes its corresponding callback. Remove assertions for the old file-service controls.

- [ ] **Step 2: Add a local-view regression test**

Create `test/local_page_view_test.dart` with a widget test that constructs `LocalPageView` using a running state and callbacks, then asserts that `状态: 运行中`, the local network address, `启动服务`/`停止服务`, `打开收到的文件`, and `删除本地文件` are present. Tap `停止服务` and assert its callback runs.

- [ ] **Step 3: Run the tests to verify the expected API is currently missing**

Run:

```bash
flutter test test/home_page_view_test.dart test/local_page_view_test.dart
```

Expected: FAIL because `HomePageView` still exposes the old local-file properties and `LocalPageView` does not exist yet.

### Task 2: Make the mobile home page a two-entry lobby

**Files:**
- Modify: `lib/home_page.dart`
- Modify: `lib/home_page_view.dart`

- [ ] **Step 1: Simplify `HomePage` to navigation only**

Remove `HomePageController`, file-service, spreadsheet, received-file, and toast imports from `lib/home_page.dart`. Keep the existing online route and add a local route:

```dart
/// 构建移动端大厅，并提供在线与本地页面入口。
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  /// 打开在线设备管理页面。
  void _showOnlinePage(BuildContext context) {
    Navigator.push<void>(
      context,
      MaterialPageRoute(builder: (_) => const OnlinePage()),
    );
  }

  /// 打开本地文件传输配置页面。
  void _showLocalPage(BuildContext context) {
    Navigator.push<void>(
      context,
      MaterialPageRoute(builder: (_) => const LocalPage()),
    );
  }

  /// 构建大厅视图并连接两个导航回调。
  @override
  Widget build(BuildContext context) {
    return HomePageView(
      onOnlinePage: () => _showOnlinePage(context),
      onLocalPage: () => _showLocalPage(context),
    );
  }
}
```

- [ ] **Step 2: Replace `HomePageView` with two navigation actions**

Change `HomePageView` to accept only `onOnlinePage` and `onLocalPage`. Render an AppBar titled `大厅` and two clearly labelled `在线` and `本地` buttons with existing Material icons. Do not retain local service state or controls in this view.

- [ ] **Step 3: Run the lobby test**

Run:

```bash
flutter test test/home_page_view_test.dart
```

Expected: PASS.

### Task 3: Move existing local functionality into `LocalPage`

**Files:**
- Modify: `lib/local_page.dart`
- Create: `lib/local_page_view.dart`

- [ ] **Step 1: Add `LocalPageView` from the existing local controls**

Move the current file-service layout from `HomePageView` into `LocalPageView`, preserving its inputs and callbacks: `status`, `localIp`, `port`, `isRunning`, `hasFiles`, `receivedNotice`, `onDeleteFiles`, `onStart`, `onStop`, and `onOpenFiles`. Set the AppBar title to `本地配置`; keep the IP/port display, service buttons, received-file action, delete action, and notice text unchanged.

- [ ] **Step 2: Implement `LocalPage` controller lifecycle and callbacks**

Move the current stateful logic from `HomePage` into `LocalPage`: create `HomePageController` in `initState`, assign the replacement confirmation callback, initialize it, connect delete/open/start/stop callbacks, preserve Excel reading and spreadsheet navigation, and dispose the controller when the page leaves the tree. Build `LocalPageView` through `AnimatedBuilder`.

- [ ] **Step 3: Run local-view and existing spreadsheet-related tests**

Run:

```bash
flutter test test/local_page_view_test.dart test/home_page_view_test.dart test/file_service_test.dart test/xls_reader_test.dart
```

Expected: PASS.

### Task 4: Analyze and verify the scoped change

**Files:**
- Verify: `lib/home_page.dart`
- Verify: `lib/home_page_view.dart`
- Verify: `lib/local_page.dart`
- Verify: `lib/local_page_view.dart`
- Verify: `test/home_page_view_test.dart`
- Verify: `test/local_page_view_test.dart`

- [ ] **Step 1: Format the changed Dart files**

Run:

```bash
dart format lib/home_page.dart lib/home_page_view.dart lib/local_page.dart lib/local_page_view.dart test/home_page_view_test.dart test/local_page_view_test.dart
```

- [ ] **Step 2: Run scoped static analysis**

Run:

```bash
flutter analyze lib/home_page.dart lib/home_page_view.dart lib/local_page.dart lib/local_page_view.dart test/home_page_view_test.dart test/local_page_view_test.dart
```

Expected: `No issues found!`.

- [ ] **Step 3: Run the scoped test suite and diff checks**

Run:

```bash
flutter test test/home_page_view_test.dart test/local_page_view_test.dart test/file_service_test.dart test/xls_reader_test.dart
git diff --check
```

Expected: all listed tests pass and `git diff --check` produces no output.

- [ ] **Step 4: Commit the implementation**

```bash
git add lib/home_page.dart lib/home_page_view.dart lib/local_page.dart lib/local_page_view.dart test/home_page_view_test.dart test/local_page_view_test.dart
git diff --cached --check
git commit -m "feat: split home lobby and local config page"
```
