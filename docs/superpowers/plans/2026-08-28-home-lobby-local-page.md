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

### Task 5: Add the Android build and fir.im API upload script

**Files:**
- Create: `scripts/build_and_upload_fir.sh`
- Create: `test/build_and_upload_fir_test.sh`

- [ ] **Step 1: Add a failure-path shell test**

Create `test/build_and_upload_fir_test.sh` that runs the release script with the placeholder token and asserts it exits non-zero with a message asking for `FIR_API_TOKEN`. The test must run from any working directory by resolving the repository root from the test file location.

- [ ] **Step 2: Run the shell test to verify the script is missing**

Run:

```bash
bash test/build_and_upload_fir_test.sh
```

Expected: FAIL because `scripts/build_and_upload_fir.sh` does not exist.

- [ ] **Step 3: Add the executable release script**

Create `scripts/build_and_upload_fir.sh` with this behavior:

```bash
#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FIR_API_TOKEN="${FIR_API_TOKEN:-YOUR_FIR_API_TOKEN}"
FIR_BUNDLE_ID="${FIR_BUNDLE_ID:-YOUR_ANDROID_BUNDLE_ID}"
FIR_API_URL="${FIR_API_URL:-http://api.appmeta.cn/apps}"
APK_PATH="${PROJECT_ROOT}/build/app/outputs/flutter-apk/app-release.apk"

if [[ "${FIR_API_TOKEN}" == "YOUR_FIR_API_TOKEN" ]]; then
  echo "请设置 FIR_API_TOKEN 后再上传 fir.im。" >&2
  exit 1
fi
if [[ "${FIR_BUNDLE_ID}" == "YOUR_ANDROID_BUNDLE_ID" ]]; then
  echo "请设置 FIR_BUNDLE_ID 后再上传 fir.im。" >&2
  exit 1
fi

command -v flutter >/dev/null 2>&1 || {
  echo "未找到 flutter 命令。" >&2
  exit 1
}
command -v curl >/dev/null 2>&1 || {
  echo "未找到 curl 命令。" >&2
  exit 1
}
command -v python3 >/dev/null 2>&1 || {
  echo "未找到 python3 命令，用于解析上传凭证。" >&2
  exit 1
}

cd "${PROJECT_ROOT}"
flutter build apk --release

if [[ ! -f "${APK_PATH}" ]]; then
  echo "未找到构建产物: ${APK_PATH}" >&2
  exit 1
fi

PUBSPEC_VERSION="$(awk '$1 == "version:" { print $2; exit }' pubspec.yaml)"
FIR_VERSION="${FIR_VERSION:-${PUBSPEC_VERSION%%+*}}"
FIR_BUILD="${FIR_BUILD:-${PUBSPEC_VERSION#*+}}"
if [[ -z "${FIR_BUILD}" || "${FIR_BUILD}" == "${PUBSPEC_VERSION}" ]]; then
  FIR_BUILD="$(date +%Y%m%d%H%M%S)"
fi

REQUEST_BODY="$(FIR_API_TOKEN="${FIR_API_TOKEN}" FIR_BUNDLE_ID="${FIR_BUNDLE_ID}" python3 - <<'PY'
import json
import os

print(json.dumps({
    'type': 'android',
    'bundle_id': os.environ['FIR_BUNDLE_ID'],
    'api_token': os.environ['FIR_API_TOKEN'],
}))
PY
)"

CREDENTIALS="$(curl --fail --silent --show-error \
  --request POST "${FIR_API_URL}" \
  --header "Content-Type: application/json" \
  --data "${REQUEST_BODY}")"

CREDENTIAL_FIELDS="$(CREDENTIALS="${CREDENTIALS}" python3 - <<'PY'
import json
import os

binary = json.loads(os.environ['CREDENTIALS'])['cert']['binary']
print('\t'.join(binary[key] for key in ('upload_url', 'key', 'token')))
PY
)
IFS=$'\t' read -r UPLOAD_URL UPLOAD_KEY UPLOAD_TOKEN <<< "${CREDENTIAL_FIELDS}"

UPLOAD_RESPONSE="$(curl --fail --silent --show-error \
  --form "key=${UPLOAD_KEY}" \
  --form "token=${UPLOAD_TOKEN}" \
  --form "file=@${APK_PATH}" \
  --form "x:name=${FIR_APP_NAME:-excel_app}" \
  --form "x:version=${FIR_VERSION}" \
  --form "x:build=${FIR_BUILD}" \
  --form "x:changelog=${FIR_CHANGELOG:-$(git log -1 --pretty=%s)}" \
  "${UPLOAD_URL}")"

if ! UPLOAD_RESPONSE="${UPLOAD_RESPONSE}" python3 - <<'PY'
import json
import os
import sys

try:
    completed = json.loads(os.environ['UPLOAD_RESPONSE']).get('is_completed') is True
except (TypeError, json.JSONDecodeError):
    completed = False
sys.exit(0 if completed else 1)
PY
then
  echo "fir.im 上传未完成: ${UPLOAD_RESPONSE}" >&2
  exit 1
fi

echo "fir.im 上传完成。"
```

Add function-level comments if the script is later split into functions; keep the current straight-line flow to avoid an unnecessary shell abstraction. Mark the file executable.

- [ ] **Step 4: Run the shell test and syntax check**

Run:

```bash
bash test/build_and_upload_fir_test.sh
bash -n scripts/build_and_upload_fir.sh
```

Expected: the placeholder-token test passes and the script has valid Bash syntax. Do not perform a real fir.im upload without the user's token and bundle ID.

- [ ] **Step 5: Commit the release script**

```bash
git add scripts/build_and_upload_fir.sh test/build_and_upload_fir_test.sh
git diff --cached --check
git commit -m "build: add fir upload script"
```
