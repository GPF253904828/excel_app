# Spreadsheet CRUD Export Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add spreadsheet CRUD interactions on the phone and send edited files back through the existing IP page without a browser page refresh.

**Architecture:** `SpreadsheetPage` owns temporary editable table state and confirmation dialogs. `XlsExporter` serializes the edited table into an Excel/WPS-readable HTML table while preserving the original `.xls` filename extension. `FileServer` exposes a polling download endpoint and changes its upload page to AJAX. The controller queues the edited export for the server.

**Tech Stack:** Flutter Material, Dart `dart:io`, existing `FileServer` and `XlsReader`, browser Fetch API.

---

### Task 1: Add serialization and editing tests

**Files:**
- Create: `test/xls_exporter_test.dart`
- Modify: `test/spreadsheet_page_test.dart`

- [x] **Step 1: Write failing exporter test**
- [x] **Step 2: Write failing spreadsheet interaction test**
- [x] **Step 3: Run both tests and verify the failures are feature-related**

### Task 2: Implement editable spreadsheet page

**Files:**
- Modify: `lib/spreadsheet_page.dart`

- [x] **Step 1: Add an add-row toolbar action**
- [x] **Step 2: Add tap-to-edit cells**
- [x] **Step 3: Add long-press delete with confirmation**
- [x] **Step 4: Add save confirmation and save callback**
- [x] **Step 5: Run spreadsheet tests**

### Task 3: Implement export and browser download polling

**Files:**
- Create: `lib/network_tools/xls_exporter.dart`
- Modify: `lib/network_tools/file_service.dart`
- Modify: `lib/home_page_controller.dart`
- Modify: `lib/home_page.dart`

- [x] **Step 1: Serialize edited rows with escaped HTML table cells**
- [x] **Step 2: Queue an edited file on the phone server**
- [x] **Step 3: Add `/export` polling download endpoint**
- [x] **Step 4: Change browser upload to Fetch and show `已发送`**
- [x] **Step 5: Run service and exporter tests**

### Task 4: Final verification

**Files:**
- Modify: relevant tests only if required by final behavior.

- [x] **Step 1: Run `dart format lib test`**
- [x] **Step 2: Run `flutter analyze`**
- [x] **Step 3: Run all focused tests for upload, parsing, export, view, and spreadsheet editing**
