# HomePage Refactor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Split `HomePage` into a small view, a `ChangeNotifier` controller, and a received-file picker while preserving the current upload and Excel workflows.

**Architecture:** `HomePageController` owns file-service lifecycle and received-file state. `HomePageView` renders the controller state and emits user actions. `ReceivedFilesSheet` owns the file-selection UI. Navigation and Excel parsing remain in `HomePage`, which becomes the composition root.

**Tech Stack:** Flutter Material widgets, Dart `ChangeNotifier`, existing `FileServer`, existing `XlsReader`.

---

### Task 1: Add a view regression test

**Files:**
- Create: `test/home_page_view_test.dart`
- Create: `lib/home_page_view.dart`

- [x] **Step 1: Write the failing test**

Verify the extracted view renders the existing title and action buttons and forwards the open-files action.

- [x] **Step 2: Run the test**

Run `flutter test test/home_page_view_test.dart`; it should fail because the extracted view does not exist yet.

- [x] **Step 3: Implement the minimal presentational view**

Move the existing `Scaffold` layout into `HomePageView`, receiving state and callbacks as constructor parameters.

- [x] **Step 4: Run the test**

Run `flutter test test/home_page_view_test.dart`; it should pass.

### Task 2: Extract HomePage state and file-service lifecycle

**Files:**
- Create: `lib/home_page_controller.dart`
- Modify: `lib/home_page.dart`

- [x] **Step 1: Move state ownership into `HomePageController`**

Move `_fileServer`, `_localIp`, `_status`, `_hasFiles`, save-directory initialization, file scanning, server start/stop, and receive callback into a `ChangeNotifier` controller.

- [x] **Step 2: Connect HomePage to the controller**

Keep `HomePage` as the composition root. Instantiate and dispose the controller, initialize it in `initState`, and rebuild `HomePageView` through `AnimatedBuilder`.

- [x] **Step 3: Preserve the file-opening workflow**

Read files from the controller, show the extracted picker, parse `.xls` with `XlsReader`, and push `SpreadsheetPage` exactly as before.

### Task 3: Extract the received-file picker

**Files:**
- Create: `lib/received_files_sheet.dart`
- Modify: `lib/home_page.dart`

- [x] **Step 1: Move the bottom-sheet file list**

Move file size calculation and `ListTile` rendering into `ReceivedFilesSheet` plus a small `showReceivedFilesSheet` helper.

- [x] **Step 2: Keep navigation in HomePage**

The picker only reports the selected `File`; HomePage remains responsible for showing errors and pushing `SpreadsheetPage`.

### Task 4: Verify the refactor

**Files:**
- Modify: `test/home_page_view_test.dart` if needed for final behavior coverage.

- [x] **Step 1: Format and analyze**

Run `dart format lib test` and `flutter analyze`. Only the pre-existing `print` info in `file_service.dart` may remain.

- [x] **Step 2: Run focused tests**

Run `flutter test test/home_page_view_test.dart test/spreadsheet_page_test.dart test/xls_reader_test.dart test/file_service_test.dart`; all tests must pass.
