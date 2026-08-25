# Spreadsheet QR Scan and Device Editing Design

## Goal

在 `spreadsheet_page` 增加二维码扫描入口。扫描到设备编码后定位现有设备行并进入统一的设备编辑页；新增操作也进入该编辑页。编辑页保存成功后立即通过现有回调更新外部列表。

## Scope

- 使用 `mobile_scanner` 打开相机并扫描二维码。
- 添加 Android 和 iOS 相机权限声明。
- 按 `设备编号` 列做去除首尾空白后的精确匹配。
- 为已有行和新增行共用一个动态表单编辑页。
- 已有行的设备编码默认只读，点击修改后必须二次确认。
- 保留现有删除、表格展示和 `XlsTable` 外部保存回调。

## Architecture

### `ScannerPage`

只负责相机预览和扫描结果。使用 `mobile_scanner` 的检测回调，在首个有效值到达后停止扫描并返回设备编码。权限拒绝、初始化失败和无法使用相机时显示提示并允许返回。

### `DeviceEditPage`

接收表头、初始行和是否为新增行，按表头动态创建输入框。编辑已有行时设备编码字段为只读；点击修改操作后弹出二次确认，确认后才允许编辑。新增行的设备编码可直接填写。保存时返回与表头等长的新行，保存失败时留在当前页面并保留输入内容。

### `SpreadsheetPage`

继续持有当前表头和行数据，并新增两个入口：

1. 扫码后按 `设备编号` 查找行。找到则打开 `DeviceEditPage`；找不到则提示并留在列表页。
2. 新增按钮打开空白 `DeviceEditPage`，不提前修改列表。

编辑页返回成功后，列表页替换原行或追加新行，然后立即调用现有 `onSave(XlsTable)` 回调。外部保存失败时不改变列表页中的数据，并将错误反馈给用户。

## Data Flow

```text
SpreadsheetPage
  -> ScannerPage -- device code --> exact row match
  -> DeviceEditPage -- edited row --> replace/append local row
  -> onSave(XlsTable) --> existing external list/file service
```

扫描页面只返回字符串，不直接修改表格；编辑页面只返回一行数据，不直接依赖文件服务。

## Permissions and Platform Configuration

- `pubspec.yaml` 添加 `mobile_scanner`。
- Android 添加 `android.permission.CAMERA`。
- iOS 添加 `NSCameraUsageDescription`，说明相机用于扫描设备二维码。

## Error Handling

- 表格没有 `设备编号` 表头时，扫码入口提示当前表格不支持扫码。
- 扫描结果为空时忽略，不打开编辑页。
- 找不到设备编码时提示 `未找到设备编号：xxx`。
- 相机权限被拒绝或扫描初始化失败时提示错误并允许返回。
- 保存失败时保留编辑页输入，允许重试；不会调用成功后的页面返回逻辑。
- 扫描成功后立即停止扫描，避免同一二维码重复触发。

## Verification

- widget test：新增不会立即增加列表行，编辑页保存后追加。
- widget test：扫码编码定位正确行；找不到时不进入编辑页。
- widget test：编辑已有行替换原行并调用外部保存回调。
- widget test：已有设备编码默认只读，二次确认后才可编辑。
- widget test：保存失败时编辑内容仍保留。
- `flutter analyze` 和 `flutter test` 验证构建、静态检查与回归。

