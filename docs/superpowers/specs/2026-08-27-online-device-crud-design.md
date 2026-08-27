# 在线设备表格 CRUD 设计

## 目标

完善 `OnlinePage`，让用户按设备编号查询在线表格中的整行设备信息，并支持通过现有接口修改、新增和删除；修改、新增复用 `DeviceEditPage`。

## 范围与边界

- 修改 `lib/online/online_page.dart`，负责在线页状态、15 列展示、操作入口和 `DeviceApi` 调用。
- 新增在线页测试，覆盖查询、编辑回写、新增、删除和失败状态。
- 只读取 `lib/online/air_script` 了解请求和返回字段，不修改脚本。
- 不修改 `lib/utils/net_util.dart`；其 `DeviceApi` 和 `DeviceResult` 是本功能的网络边界。
- 不改变本地 `SpreadsheetPage` 的行为。

## 固定列

在线页始终按以下顺序展示字段，返回数据缺少字段时显示为空：

`归属部门`、`来源`、`设备状态`、`设备编号`、`设备名称`、`设备型号`、`机身号`、`生产厂家`、`所在区域`、`所在房间`、`设备分类`、`设备负责人`、`计量机构`、`证书类型`、`计量有效期至`

## 数据流

1. 用户在输入框输入设备编号并点击查询。
2. 页面调用 `DeviceApi.queryDevice(no)`；成功后把 `DeviceResult.data` 映射到固定列并展示，失败时展示接口消息。
3. 修改按钮打开 `DeviceEditPage`，传入固定列和当前整行值。编辑器保存时将整行转为 `{表头: 值}`，调用 `DeviceApi.modifyDevice(originalNo, data)`。接口成功后以返回的 `data` 更新结果并提示成功；失败时保留编辑页和原结果。
4. 新增按钮打开空白 `DeviceEditPage`。保存时调用 `DeviceApi.addDevice(data)`；接口成功后展示返回的新行并提示成功，失败时保留编辑页。
5. 查询成功结果显示删除按钮。二次确认后调用 `DeviceApi.deleteDevice(no)`；接口成功后清空结果但保留输入框内容，失败时保留结果并提示失败。

## 状态与错误处理

- `_loading` 防止查询、修改、新增、删除重复提交；异步结束前检查 `mounted`。
- `DeviceResult.success == false` 视为业务失败，使用 `errorMessage` 展示原因，不更新页面数据。
- `DeviceApiException` 或其他异常展示异常文本，不清空已有结果。
- 删除成功只清除当前结果和操作提示，不清除设备编号输入框。

## 测试策略

- 用 `DeviceApi` 可替换的调用边界测试页面行为，避免真实请求。
- 查询成功验证 15 个字段按固定顺序展示，查询失败验证错误消息。
- 修改和新增验证 `DeviceEditPage` 打开、完整数据映射、成功后结果更新，以及失败后编辑页保持打开。
- 删除验证二次确认、接口调用、成功后结果清空且输入值保留，以及失败后结果保留。
- 运行 `flutter test`、`flutter analyze`，并用 `git diff --check` 和差异检查确认 `lib/online/air_script` 未修改。
