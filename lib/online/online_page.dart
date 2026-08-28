import 'package:excel_app/device_edit_page.dart';
import 'package:excel_app/utils/net_util.dart';
import 'package:flutter/material.dart';

/// 在线设备表格固定展示的字段顺序。
const List<String> onlineDeviceHeaders = <String>[
  '归属部门',
  '来源',
  '设备状态',
  '设备编号',
  '设备名称',
  '设备型号',
  '机身号',
  '生产厂家',
  '所在区域',
  '所在房间',
  '设备分类',
  '设备负责人',
  '计量机构',
  '证书类型',
  '计量有效期至',
];

/// 页面字段到 WPS 脚本表头的兼容名称。
const Map<String, List<String>> _onlineDeviceFieldAliases =
    <String, List<String>>{
  '归属部门': <String>['归属部门', '部门'],
  '设备状态': <String>['设备状态', '状态'],
  '设备负责人': <String>['设备负责人', '仪器设备负责人'],
};

/// 新增请求默认使用脚本当前表格中的实际表头名称。
const Map<String, String> _defaultOnlineApiKeys = <String, String>{
  '归属部门': '部门',
  '设备状态': '状态',
  '设备负责人': '仪器设备负责人',
};

/// 定义在线设备查询接口的可替换回调。
typedef DeviceQueryCallback = Future<DeviceResult> Function(String deviceNo);

/// 定义在线设备修改接口的可替换回调。
typedef DeviceModifyCallback = Future<DeviceResult> Function(
  String deviceNo,
  Map<String, dynamic> data,
);

/// 定义在线设备新增接口的可替换回调。
typedef DeviceAddCallback = Future<DeviceResult> Function(
  Map<String, dynamic> data,
);

/// 定义在线设备删除接口的可替换回调。
typedef DeviceDeleteCallback = Future<DeviceResult> Function(String deviceNo);

/// 提供在线设备的查询、修改、新增和删除操作。
class OnlinePage extends StatefulWidget {
  final DeviceQueryCallback? onQuery;
  final DeviceModifyCallback? onModify;
  final DeviceAddCallback? onAdd;
  final DeviceDeleteCallback? onDelete;

  /// Creates an online device page with optional API callbacks for testing.
  const OnlinePage({
    super.key,
    this.onQuery,
    this.onModify,
    this.onAdd,
    this.onDelete,
  });

  /// Creates the mutable state for this online device page.
  @override
  State<OnlinePage> createState() => _OnlinePageState();
}

class _OnlinePageState extends State<OnlinePage> {
  final TextEditingController _controller = TextEditingController();
  bool _loading = false;
  Map<String, String>? _data;
  Map<String, String> _apiKeys = <String, String>{};
  String? _deviceNo;
  String? _error;
  String? _notice;

  /// Releases the device number input controller.
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Calls the injected query callback or the production API implementation.
  Future<DeviceResult> _queryApi(String deviceNo) {
    return widget.onQuery?.call(deviceNo) ?? DeviceApi.queryDevice(deviceNo);
  }

  /// Calls the injected modify callback or the production API implementation.
  Future<DeviceResult> _modifyApi(
    String deviceNo,
    Map<String, dynamic> data,
  ) {
    return widget.onModify?.call(deviceNo, data) ??
        DeviceApi.modifyDevice(deviceNo, data);
  }

  /// Calls the injected add callback or the production API implementation.
  Future<DeviceResult> _addApi(Map<String, dynamic> data) {
    return widget.onAdd?.call(data) ?? DeviceApi.addDevice(data);
  }

  /// Calls the injected delete callback or the production API implementation.
  Future<DeviceResult> _deleteApi(String deviceNo) {
    return widget.onDelete?.call(deviceNo) ?? DeviceApi.deleteDevice(deviceNo);
  }

  /// Converts a failed business result into the exception used by the editor.
  void _throwIfFailed(DeviceResult result) {
    if (!result.success) {
      throw DeviceApiException(result.errorMessage ?? '操作失败');
    }
  }

  /// Normalizes API data to the fixed online table columns.
  Map<String, String> _normalizeData(
    Map<String, dynamic>? data, {
    Map<String, dynamic>? fallback,
  }) {
    final source = data ?? fallback ?? <String, dynamic>{};
    final resolvedKeys = <String, String>{};
    final normalized = <String, String>{};
    for (final header in onlineDeviceHeaders) {
      final key = _findApiKey(header, data ?? <String, dynamic>{}) ??
          _apiKeys[header] ??
          _defaultOnlineApiKeys[header] ??
          header;
      resolvedKeys[header] = key;
      normalized[header] = source.containsKey(key)
          ? (source[key] ?? '').toString()
          : (fallback?[header] ?? '').toString();
    }
    if (data != null && data.isNotEmpty) _apiKeys = resolvedKeys;
    return normalized;
  }

  /// Finds the first compatible script key present in an API response.
  String? _findApiKey(String header, Map<String, dynamic> source) {
    final aliases = _onlineDeviceFieldAliases[header] ?? <String>[header];
    for (final alias in aliases) {
      if (source.containsKey(alias)) return alias;
    }
    return source.containsKey(header) ? header : null;
  }

  /// Converts one edited row into the column-to-value payload expected by the script.
  Map<String, dynamic> _rowToData(List<String> row) {
    return <String, dynamic>{
      for (var index = 0; index < onlineDeviceHeaders.length; index++)
        _apiKeys[onlineDeviceHeaders[index]] ??
            _defaultOnlineApiKeys[onlineDeviceHeaders[index]] ??
            onlineDeviceHeaders[index]: index < row.length ? row[index] : '',
    };
  }

  /// Returns a human-readable message for an API or transport exception.
  String _errorText(Object error) {
    if (error is DeviceApiException) return error.message;
    return error.toString();
  }

  /// Queries the remote table by the device number in the input field.
  Future<void> _query() async {
    if (_loading) return;
    final no = _controller.text.trim();
    if (no.isEmpty) {
      setState(() {
        _error = '请输入设备编号';
        _notice = null;
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
      _notice = null;
    });
    try {
      final result = await _queryApi(no);
      if (!mounted) return;
      if (!result.success) {
        setState(() => _error = result.errorMessage ?? '查询失败');
        return;
      }
      setState(() {
        _data = _normalizeData(result.data);
        _deviceNo = result.deviceNo ?? no;
        _notice = '查询成功';
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = _errorText(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Opens the shared editor for a new row or the currently queried row.
  Future<void> _openEditor({required bool isNew}) async {
    if (_loading) return;
    final initialRow = isNew
        ? List<String>.filled(onlineDeviceHeaders.length, '')
        : onlineDeviceHeaders.map((header) => _data?[header] ?? '').toList();

    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => DeviceEditPage(
          headers: List<String>.from(onlineDeviceHeaders),
          initialRow: initialRow,
          isNew: isNew,
          onSave: isNew
              ? _saveAddedRow
              : (row) => _saveModifiedRow(_deviceNo!, row),
        ),
      ),
    );
  }

  /// Saves an edited existing row through the remote modify operation.
  Future<void> _saveModifiedRow(String originalNo, List<String> row) async {
    if (_loading) return;
    final data = _rowToData(row);
    setState(() {
      _loading = true;
      _error = null;
      _notice = null;
    });
    try {
      final result = await _modifyApi(originalNo, data);
      _throwIfFailed(result);
      if (!mounted) return;
      final updated = _normalizeData(result.data, fallback: data);
      setState(() {
        _data = updated;
        _deviceNo = result.deviceNo ?? updated['设备编号'] ?? originalNo;
        _notice = '修改成功';
        _error = null;
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Saves a new complete row through the remote add operation.
  Future<void> _saveAddedRow(List<String> row) async {
    if (_loading) return;
    final data = _rowToData(row);
    setState(() {
      _loading = true;
      _error = null;
      _notice = null;
    });
    try {
      final result = await _addApi(data);
      _throwIfFailed(result);
      if (!mounted) return;
      final added = _normalizeData(result.data, fallback: data);
      final addedNo = result.deviceNo ?? added['设备编号'] ?? '';
      _controller.text = addedNo;
      setState(() {
        _data = added;
        _deviceNo = addedNo;
        _notice = '新增成功';
        _error = null;
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Confirms and deletes the currently queried device row.
  Future<void> _delete() async {
    final no = _deviceNo;
    if (_loading || no == null || _data == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('确认删除设备'),
        content: Text('确定删除设备编号 $no 吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('确认删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _loading = true;
      _error = null;
      _notice = null;
    });
    try {
      final result = await _deleteApi(no);
      _throwIfFailed(result);
      if (!mounted) return;
      setState(() {
        _data = null;
        _notice = '删除成功';
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = _errorText(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Builds the two-column table for the queried device row.
  Widget _buildResult() {
    final data = _data!;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Table(
              border: TableBorder.all(
                color: Theme.of(context).dividerColor,
              ),
              columnWidths: const {
                0: FixedColumnWidth(116),
                1: FlexColumnWidth(),
              },
              children: [
                for (final header in onlineDeviceHeaders)
                  TableRow(
                    children: [
                      Container(
                        key: Key('online-column-$header'),
                        color: Theme.of(context).colorScheme.surfaceVariant,
                        padding: const EdgeInsets.all(10),
                        child: Text(
                          header,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      Container(
                        key: Key('online-value-$header'),
                        padding: const EdgeInsets.all(10),
                        child: Text(data[header] ?? ''),
                      ),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    key: const Key('online-edit'),
                    onPressed:
                        _loading ? null : () => _openEditor(isNew: false),
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('修改'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    key: const Key('online-delete'),
                    onPressed: _loading ? null : _delete,
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('删除'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Builds the online page input, operation buttons, status and result table.
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('设备查询')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: const Key('online-device-no'),
                      controller: _controller,
                      textInputAction: TextInputAction.search,
                      onSubmitted: (_) => _query(),
                      decoration: const InputDecoration(
                        labelText: '设备编号',
                        hintText: '请输入设备编号',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilledButton.icon(
                    key: const Key('online-query'),
                    onPressed: _loading ? null : _query,
                    icon: _loading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.search),
                    label: const Text('查询'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  key: const Key('online-add'),
                  onPressed: _loading ? null : () => _openEditor(isNew: true),
                  icon: const Icon(Icons.add),
                  label: const Text('新增设备'),
                ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Card(
                    color: Theme.of(context).colorScheme.errorContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(_error!),
                    ),
                  ),
                ),
              if (_notice != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    _notice!,
                    key: const Key('online-notice'),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              if (_data != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: _buildResult(),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
