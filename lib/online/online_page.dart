import 'dart:io';
import 'dart:typed_data';

import 'package:excel_app/network_tools/xls_reader.dart';
import 'package:excel_app/online/online_config_page.dart';
import 'package:excel_app/online/online_config_store.dart';
import 'package:excel_app/qr_create_page.dart';
import 'package:excel_app/spreadsheet_page.dart';
import 'package:excel_app/utils/net_util.dart';
import 'package:excel_app/utils/toast_util.dart';
import 'package:flutter/material.dart';

/// 在线设备表格的默认字段顺序，也是空列表新增设备时使用的字段集合。
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

/// 返回固定业务字段优先、接口额外字段追加的在线表格列序。
List<String> onlineTableHeaders(List<Map<String, dynamic>> rows) {
  final headers = List<String>.from(onlineDeviceHeaders);
  for (final row in rows) {
    for (final header in row.keys) {
      if (!headers.contains(header)) headers.add(header);
    }
  }
  return headers;
}

/// 定义在线设备列表接口的可替换回调。
typedef DeviceListCallback = Future<DeviceListResult> Function();

/// 定义设备修改接口的可替换回调。
typedef DeviceModifyCallback = Future<DeviceResult> Function(
  String deviceNo,
  Map<String, dynamic> data,
);

/// 定义设备新增接口的可替换回调。
typedef DeviceAddCallback = Future<DeviceResult> Function(
  Map<String, dynamic> data,
);

/// 定义设备删除接口的可替换回调。
typedef DeviceDeleteCallback = Future<DeviceResult> Function(String deviceNo);

/// 提供在线设备列表、远程行操作和二维码导出入口。
class OnlinePage extends StatefulWidget {
  final DeviceListCallback? onList;
  final DeviceModifyCallback? onModify;
  final DeviceAddCallback? onAdd;
  final DeviceDeleteCallback? onDelete;
  final QrExportPageBuilder? qrExportPageBuilder;
  final OnlineConfigStore configStore;

  const OnlinePage({
    super.key,
    this.onList,
    this.onModify,
    this.onAdd,
    this.onDelete,
    this.qrExportPageBuilder,
    this.configStore = const OnlineConfigStore(),
  });

  @override
  State<OnlinePage> createState() => _OnlinePageState();
}

class _OnlinePageState extends State<OnlinePage> {
  OnlineApiConfig? _apiConfig;
  XlsTable? _table;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  /// 读取活动配置并加载首次在线列表。
  Future<void> _initialize() async {
    try {
      await _loadConfig();
      await _loadList();
    } catch (_) {
      // 错误信息已由 _loadList 写入状态供页面展示。
    }
  }

  /// 从持久化存储读取当前活动配置。
  Future<void> _loadConfig() async {
    final config = await widget.configStore.load();
    if (mounted) setState(() => _apiConfig = config);
  }

  /// 打开配置列表，确认切换后重新拉取线上数据。
  Future<void> _openConfig() async {
    final config = await Navigator.push<OnlineApiConfig>(
      context,
      MaterialPageRoute(
        builder: (_) => OnlineConfigPage(store: widget.configStore),
      ),
    );
    if (config == null || !mounted) return;
    setState(() => _apiConfig = config);
    await _refresh();
  }

  /// 手动刷新列表，并将错误转为短提示。
  Future<void> _refresh() async {
    try {
      await _loadList();
    } catch (error) {
      if (mounted) ToastUtil.showCenter(_errorText(error));
    }
  }

  /// 返回已确认的活动配置，缺失时终止远程操作。
  Future<OnlineApiConfig> _requireConfig() async {
    final config = _apiConfig ?? await widget.configStore.load();
    if (config == null) throw DeviceApiException('请先选择接口配置');
    if (mounted && _apiConfig == null) setState(() => _apiConfig = config);
    return config;
  }

  /// 调用注入的列表回调或生产接口。
  Future<DeviceListResult> _listApi() async {
    if (widget.onList != null) return widget.onList!();
    final config = await _requireConfig();
    return DeviceApi.listDevices(webhook: config.url, token: config.token);
  }

  /// 调用注入的修改回调或生产接口。
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

  /// 调用注入的新增回调或生产接口。
  Future<DeviceResult> _addApi(Map<String, dynamic> data) async {
    if (widget.onAdd != null) return widget.onAdd!(data);
    final config = await _requireConfig();
    return DeviceApi.addDevice(data, webhook: config.url, token: config.token);
  }

  /// 调用注入的删除回调或生产接口。
  Future<DeviceResult> _deleteApi(String deviceNo) async {
    if (widget.onDelete != null) return widget.onDelete!(deviceNo);
    final config = await _requireConfig();
    return DeviceApi.deleteDevice(
      deviceNo,
      webhook: config.url,
      token: config.token,
    );
  }

  /// 加载远程 rows 并生成能包含全部字段的表格数据。
  Future<XlsTable> _loadList() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final result = await _listApi();
      if (!result.success) {
        throw DeviceApiException(result.errorMessage ?? '加载列表失败');
      }
      final table = _tableFromRows(result.rows);
      if (mounted) setState(() => _table = table);
      return table;
    } catch (error) {
      if (mounted) setState(() => _error = _errorText(error));
      rethrow;
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// 依据接口返回的字段顺序构造二维表格，保留所有额外列。
  XlsTable _tableFromRows(List<Map<String, dynamic>> rows) {
    final headers = onlineTableHeaders(rows);
    return XlsTable(
      headers: headers,
      rows: <List<String>>[
        for (final row in rows)
          <String>[
            for (final header in headers) (row[header] ?? '').toString()
          ],
      ],
    );
  }

  /// 将编辑行按当前表头转换为脚本接口所需的字段载荷。
  Map<String, dynamic> _rowToData(List<String> row) {
    final headers = _table?.headers ?? onlineDeviceHeaders;
    return <String, dynamic>{
      for (var index = 0; index < headers.length; index++)
        headers[index]: index < row.length ? row[index] : '',
    };
  }

  /// 从当前表头和行中取得设备编号，作为修改和删除的定位键。
  String _deviceNo(List<String> row) {
    final headers = _table?.headers ?? onlineDeviceHeaders;
    final index = headers.indexOf('设备编号');
    if (index < 0 || index >= row.length || row[index].trim().isEmpty) {
      throw DeviceApiException('设备编号不能为空');
    }
    return row[index].trim();
  }

  /// 提交新增或修改后重新拉取完整线上列表。
  Future<XlsTable> _saveRemoteRow(int? rowIndex, List<String> row) async {
    final result = rowIndex == null
        ? await _addApi(_rowToData(row))
        : await _modifyApi(_deviceNo(row), _rowToData(row));
    if (!result.success) {
      throw DeviceApiException(result.errorMessage ?? '保存失败');
    }
    return _loadList();
  }

  /// 删除远程行后重新拉取完整线上列表。
  Future<XlsTable> _deleteRemoteRow(int rowIndex, List<String> row) async {
    final result = await _deleteApi(_deviceNo(row));
    if (!result.success) {
      throw DeviceApiException(result.errorMessage ?? '删除失败');
    }
    return _loadList();
  }

  /// 将业务或传输异常转换为页面可读消息。
  String _errorText(Object error) {
    if (error is DeviceApiException) return error.message;
    return error.toString();
  }

  /// 创建在线表格使用的统一工具栏操作。
  List<Widget> _tableActions() => <Widget>[
        IconButton(
          key: const Key('online-config'),
          onPressed: _loading ? null : _openConfig,
          tooltip: '接口配置',
          icon: const Icon(Icons.settings_outlined),
        ),
        IconButton(
          key: const Key('online-refresh'),
          onPressed: _loading ? null : _refresh,
          tooltip: '刷新列表',
          icon: const Icon(Icons.refresh),
        ),
      ];

  /// 构建列表加载过程中的状态页面。
  Widget _buildLoadingPage() => Scaffold(
        appBar: AppBar(
          title: const Text('在线设备'),
          actions: _tableActions(),
        ),
        body: Center(
          child: _loading
              ? const CircularProgressIndicator()
              : Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(_error ?? '暂无数据'),
                ),
        ),
      );

  /// 构建在线表格或首次加载状态。
  @override
  Widget build(BuildContext context) {
    final table = _table;
    if (table == null) return _buildLoadingPage();
    return SpreadsheetPage(
      file: File('online_devices.xls'),
      table: table,
      title: '在线设备',
      appBarActions: _tableActions(),
      onSaveRow: _saveRemoteRow,
      onDeleteRow: _deleteRemoteRow,
      qrExportPageBuilder: widget.qrExportPageBuilder,
    );
  }
}
