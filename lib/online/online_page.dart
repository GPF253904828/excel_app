import 'package:excel_app/device_edit_page.dart';
import 'package:excel_app/online/online_config_page.dart';
import 'package:excel_app/online/online_config_store.dart';
import 'package:excel_app/utils/net_util.dart';
import 'package:flutter/material.dart';

/// 在线设备表格固定展示的字段顺序。
const List<String> onlineDeviceHeaders = <String>[
  '部门',
  '来源',
  '状态',
  '设备编号',
  '设备名称',
  '设备型号',
  '机身号',
  '生产厂家',
  '所在区域',
  '所在房间',
  '设备分类',
  '仪器设备负责人',
  '计量机构',
  '证书类型',
  '计量有效期至',
];

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
  final OnlineConfigStore configStore;

  /// Creates an online device page with optional API callbacks for testing.
  const OnlinePage({
    super.key,
    this.onQuery,
    this.onModify,
    this.onAdd,
    this.onDelete,
    this.configStore = const OnlineConfigStore(),
  });

  /// Creates the mutable state for this online device page.
  @override
  State<OnlinePage> createState() => _OnlinePageState();
}

class _OnlinePageState extends State<OnlinePage> {
  final TextEditingController _controller = TextEditingController();
  bool _loading = false;
  Map<String, String>? _data;
  OnlineApiConfig? _apiConfig;
  String? _deviceNo;
  String? _error;
  String? _notice;

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  /// Releases the device number input controller.
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// 读取上次保存的接口配置并刷新当前文件名称。
  Future<void> _loadConfig() async {
    final config = await widget.configStore.load();
    if (mounted) setState(() => _apiConfig = config);
  }

  /// 打开接口配置页，并在保存后更新当前连接配置。
  Future<void> _openConfig() async {
    final config = await Navigator.push<OnlineApiConfig>(
      context,
      MaterialPageRoute(
        builder: (_) => OnlineConfigPage(store: widget.configStore),
      ),
    );
    if (mounted && config != null) setState(() => _apiConfig = config);
  }

  /// 返回已保存的接口配置，未配置时终止当前操作。
  Future<OnlineApiConfig> _requireConfig() async {
    final config = _apiConfig ?? await widget.configStore.load();
    if (config == null) throw DeviceApiException('请先配置接口 URL 和 Token');
    if (mounted && _apiConfig == null) setState(() => _apiConfig = config);
    return config;
  }

  /// Calls the injected query callback or the production API implementation.
  Future<DeviceResult> _queryApi(String deviceNo) async {
    if (widget.onQuery != null) return widget.onQuery!(deviceNo);
    final config = await _requireConfig();
    return DeviceApi.queryDevice(
      deviceNo,
      webhook: config.url,
      token: config.token,
    );
  }

  /// Calls the injected modify callback or the production API implementation.
  Future<DeviceResult> _modifyApi(
    String deviceNo,
    Map<String, dynamic> data,
  ) async {
    if (widget.onModify != null) return widget.onModify!(deviceNo, data);
    final config = await _requireConfig();
    return DeviceApi.modifyDevice(
      deviceNo,
      data,
      webhook: config.url,
      token: config.token,
    );
  }

  /// Calls the injected add callback or the production API implementation.
  Future<DeviceResult> _addApi(Map<String, dynamic> data) async {
    if (widget.onAdd != null) return widget.onAdd!(data);
    final config = await _requireConfig();
    return DeviceApi.addDevice(
      data,
      webhook: config.url,
      token: config.token,
    );
  }

  /// Calls the injected delete callback or the production API implementation.
  Future<DeviceResult> _deleteApi(String deviceNo) async {
    if (widget.onDelete != null) return widget.onDelete!(deviceNo);
    final config = await _requireConfig();
    return DeviceApi.deleteDevice(
      deviceNo,
      webhook: config.url,
      token: config.token,
    );
  }

  /// Converts a failed business result into the exception used by the editor.
  void _throwIfFailed(DeviceResult result) {
    if (!result.success) {
      throw DeviceApiException(result.errorMessage ?? '操作失败');
    }
  }

  /// 使用脚本真实表头整理接口数据到页面表格。
  Map<String, String> _normalizeData(
    Map<String, dynamic>? data, {
    Map<String, dynamic>? fallback,
  }) {
    final source = data ?? fallback ?? <String, dynamic>{};
    final normalized = <String, String>{};
    for (final header in onlineDeviceHeaders) {
      normalized[header] = source.containsKey(header)
          ? (source[header] ?? '').toString()
          : (fallback?[header] ?? '').toString();
    }
    return normalized;
  }

  /// 将编辑行直接转换为脚本真实表头的字段载荷。
  Map<String, dynamic> _rowToData(List<String> row) {
    return <String, dynamic>{
      for (var index = 0; index < onlineDeviceHeaders.length; index++)
        onlineDeviceHeaders[index]: index < row.length ? row[index] : '',
    };
  }

  /// Returns a human-readable message for an API or transport exception.
  String _errorText(Object error) {
    if (error is DeviceApiException) return error.message;
    return error.toString();
  }

  /// Removes focus from the current input when another page area is tapped.
  void _dismissKeyboard() {
    FocusManager.instance.primaryFocus?.unfocus();
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
    return GestureDetector(
      onTap: _dismissKeyboard,
      child: Scaffold(
        appBar: AppBar(
          title: GestureDetector(
            onTap: _dismissKeyboard,
            child: const Text('设备查询'),
          ),
          actions: [
            IconButton(
              key: const Key('online-config'),
              onPressed: _openConfig,
              icon: const Icon(Icons.settings_outlined),
              tooltip: '接口配置',
            ),
          ],
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '当前文件: ${_apiConfig?.fileName ?? '未配置'}',
                  key: const Key('online-current-file'),
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        key: const Key('online-device-no'),
                        controller: _controller,
                        textInputAction: TextInputAction.search,
                        onSubmitted: (_) => _query(),
                        onTapOutside: (_) => _dismissKeyboard(),
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
      ),
    );
  }
}
