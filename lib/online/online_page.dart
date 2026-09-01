// ignore_for_file: avoid_print

import 'dart:io';

import 'package:excel_app/network_tools/xls_reader.dart';
import 'package:excel_app/online/online_config_page.dart';
import 'package:excel_app/online/online_config_store.dart';
import 'package:excel_app/qr_create_page.dart';
import 'package:excel_app/spreadsheet_page.dart';
import 'package:excel_app/utils/net_util.dart';
import 'package:excel_app/utils/toast_util.dart';
import 'package:flutter/material.dart';

/// 在线设备表格的优先显示顺序；实际显示字段以接口返回的表头为准。
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

/// 按优先顺序重排接口返回字段，不补充或映射接口中不存在的列。
List<String> onlineTableHeaders(List<Map<String, dynamic>> rows) {
  final returnedHeaders = <String>[];
  final seenHeaders = <String>{};
  for (final row in rows) {
    for (final header in row.keys) {
      if (seenHeaders.add(header)) returnedHeaders.add(header);
    }
  }
  if (returnedHeaders.isEmpty) return List<String>.from(onlineDeviceHeaders);
  return <String>[
    for (final header in onlineDeviceHeaders)
      if (seenHeaders.contains(header)) header,
    for (final header in returnedHeaders)
      if (!onlineDeviceHeaders.contains(header)) header,
  ];
}

/// 定义带分页参数的在线设备列表可替换回调。
typedef DeviceListCallback = Future<DeviceListResult> Function({
  required int start,
  required int limit,
});

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
  static const int _pageSize = 100;

  OnlineApiConfig? _apiConfig;
  XlsTable? _table;
  final List<Map<String, dynamic>> _rows = <Map<String, dynamic>>[];
  String? _error;
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = false;
  int _nextStart = 0;
  int? _total;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  /// 读取活动配置并自动加载第一页在线列表。
  Future<void> _initialize() async {
    print('[Online][initialize] start');
    try {
      await _loadConfig();
      await _loadFirstPage();
      print('[Online][initialize] completed');
    } catch (error) {
      print('[Online][initialize][error] $error');
      // 错误信息已由 _loadPage 写入状态供页面展示。
    }
  }

  /// 从持久化存储读取当前活动配置。
  Future<void> _loadConfig() async {
    final config = await widget.configStore.load();
    if (mounted) setState(() => _apiConfig = config);
    print('[Online][config] loaded: ${config?.toJson()}');
  }

  /// 打开配置列表，确认切换后清空当前数据等待用户手动刷新。
  Future<void> _openConfig() async {
    print('[Online][config] open');
    final config = await Navigator.push<OnlineApiConfig>(
      context,
      MaterialPageRoute(
        builder: (_) => OnlineConfigPage(store: widget.configStore),
      ),
    );
    if (config == null) {
      print('[Online][config] selection cancelled');
      return;
    }
    if (!mounted) return;
    print('[Online][config] selected: ${config.toJson()}');
    setState(() {
      _apiConfig = config;
      _resetRows();
    });
  }

  /// 手动清空列表并重新加载第一页，将错误转为短提示。
  Future<void> _refresh() async {
    print('[Online][refresh] start');
    try {
      await _loadFirstPage();
      print('[Online][refresh] completed');
    } catch (error) {
      print('[Online][refresh][error] $error');
      if (mounted) ToastUtil.showCenter(_errorText(error));
    }
  }

  /// 返回已确认的活动配置，缺失时终止远程操作。
  Future<OnlineApiConfig> _requireConfig() async {
    final config = _apiConfig ?? await widget.configStore.load();
    if (config == null) throw DeviceApiException('请先选择接口配置');
    if (mounted && _apiConfig == null) setState(() => _apiConfig = config);
    print('[Online][config] using: ${config.toJson()}');
    return config;
  }

  /// 调用注入的列表回调或生产接口获取指定页。
  Future<DeviceListResult> _listApi({
    required int start,
    required int limit,
  }) async {
    if (widget.onList != null) {
      print('[Online][list] using injected callback start=$start limit=$limit');
      return widget.onList!(start: start, limit: limit);
    }
    final config = await _requireConfig();
    return DeviceApi.listDevices(
      webhook: config.url,
      token: config.token,
      start: start,
      limit: limit,
    );
  }

  /// 调用注入的修改回调或生产接口。
  Future<DeviceResult> _modifyApi(
    String deviceNo,
    Map<String, dynamic> data,
  ) async {
    print('[Online][modify] deviceNo=$deviceNo data=$data');
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
    print('[Online][add] data=$data');
    if (widget.onAdd != null) return widget.onAdd!(data);
    final config = await _requireConfig();
    return DeviceApi.addDevice(data, webhook: config.url, token: config.token);
  }

  /// 调用注入的删除回调或生产接口。
  Future<DeviceResult> _deleteApi(String deviceNo) async {
    print('[Online][delete] deviceNo=$deviceNo');
    if (widget.onDelete != null) return widget.onDelete!(deviceNo);
    final config = await _requireConfig();
    return DeviceApi.deleteDevice(
      deviceNo,
      webhook: config.url,
      token: config.token,
    );
  }

  /// 清空当前数据并加载分页列表的首页。
  Future<void> _loadFirstPage() => _loadPage(start: 0, replace: true);

  /// 在用户上拉到底部时追加下一页，不根据本页条数猜测是否结束。
  Future<void> _loadMore() async {
    if (_loading || _loadingMore || !_hasMore) return;
    try {
      await _loadPage(start: _nextStart, replace: false);
    } catch (error) {
      if (mounted) ToastUtil.showCenter(_errorText(error));
    }
  }

  /// 请求一页远端数据，并根据 hasMore 更新下一页的起始位置。
  Future<void> _loadPage({required int start, required bool replace}) async {
    print('[Online][list] start=$start replace=$replace');
    if (mounted) {
      setState(() {
        if (replace) _resetRows();
        _loading = replace;
        _loadingMore = !replace;
        _error = null;
      });
    }
    try {
      final result = await _listApi(start: start, limit: _pageSize);
      if (!result.success) {
        throw DeviceApiException(result.errorMessage ?? '加载列表失败');
      }
      print(
        '[Online][list] response start=${result.start} limit=${result.limit} '
        'rows=${result.rows.length} total=${result.total} hasMore=${result.hasMore}',
      );
      if (mounted) {
        setState(() {
          if (replace) _rows.clear();
          _appendRows(result.rows);
          _hasMore = result.hasMore;
          _nextStart = result.nextStart ??
              ((result.start ?? start) + (result.limit ?? _pageSize));
          _total = result.total;
          _table = _tableFromRows(_rows);
        });
      }
    } catch (error) {
      print('[Online][list][error] $error');
      if (mounted) setState(() => _error = _errorText(error));
      rethrow;
    } finally {
      print('[Online][list] finished');
      if (mounted) {
        setState(() {
          _loading = false;
          _loadingMore = false;
        });
      }
    }
  }

  /// 清空当前分页数据和状态，保留默认表头供用户手动刷新。
  void _resetRows() {
    _rows.clear();
    _hasMore = false;
    _nextStart = 0;
    _total = null;
    _table = _tableFromRows(_rows);
  }

  /// 追加尚未存在的设备行，避免本地新增与后续分页结果重复。
  void _appendRows(Iterable<Map<String, dynamic>> rows) {
    final deviceNumbers = <String>{
      for (final row in _rows) row['设备编号']?.toString().trim() ?? '',
    };
    for (final row in rows) {
      final copy = Map<String, dynamic>.from(row);
      final deviceNo = copy['设备编号']?.toString().trim() ?? '';
      if (deviceNo.isNotEmpty && deviceNumbers.contains(deviceNo)) continue;
      _rows.add(copy);
      if (deviceNo.isNotEmpty) deviceNumbers.add(deviceNo);
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

  /// 提交新增或修改后以接口返回的行数据更新当前列表，不触发重新加载。
  Future<XlsTable> _saveRemoteRow(int? rowIndex, List<String> row) async {
    print('[Online][save] rowIndex=$rowIndex row=$row');
    final data = _rowToData(row);
    final deviceNo = rowIndex == null ? null : _deviceNo(row);
    final result = rowIndex == null
        ? await _addApi(data)
        : await _modifyApi(deviceNo!, data);
    if (!result.success) {
      print('[Online][save][error] result=${result.raw}');
      throw DeviceApiException(result.errorMessage ?? '保存失败');
    }
    final updatedData = <String, dynamic>{
      ...data,
      ...?result.data,
    };
    if (rowIndex == null) {
      _appendRows(<Map<String, dynamic>>[updatedData]);
      if (_total != null) _total = _total! + 1;
    } else if (rowIndex < _rows.length) {
      _rows[rowIndex] = <String, dynamic>{..._rows[rowIndex], ...updatedData};
    }
    print('[Online][save] completed result=${result.raw}');
    return _applyLocalRows();
  }

  /// 删除远程行后从当前列表移除该行，不触发重新加载。
  Future<XlsTable> _deleteRemoteRow(int rowIndex, List<String> row) async {
    final deviceNo = _deviceNo(row);
    print('[Online][delete] rowIndex=$rowIndex deviceNo=$deviceNo');
    final result = await _deleteApi(deviceNo);
    if (!result.success) {
      print('[Online][delete][error] result=${result.raw}');
      throw DeviceApiException(result.errorMessage ?? '删除失败');
    }
    _rows.removeAt(rowIndex);
    if (_nextStart > 0) _nextStart--;
    if (_total != null && _total! > 0) _total = _total! - 1;
    print('[Online][delete] completed result=${result.raw}');
    return _applyLocalRows();
  }

  /// 从本地分页行重建表格并通知页面刷新。
  XlsTable _applyLocalRows() {
    final table = _tableFromRows(_rows);
    if (mounted) setState(() => _table = table);
    return table;
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
          onPressed: _loading || _loadingMore ? null : _openConfig,
          tooltip: '接口配置',
          icon: const Icon(Icons.settings_outlined),
        ),
        IconButton(
          key: const Key('online-refresh'),
          onPressed: _loading || _loadingMore ? null : _refresh,
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
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: const <Widget>[
                    CircularProgressIndicator(),
                    SizedBox(height: 12),
                    Text('Loading...'),
                  ],
                )
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
    if (table == null || (_error != null && _rows.isEmpty)) {
      return _buildLoadingPage();
    }
    return SpreadsheetPage(
      file: File('online_devices.xls'),
      table: table,
      title: '在线设备',
      appBarActions: _tableActions(),
      onSaveRow: _saveRemoteRow,
      onDeleteRow: _deleteRemoteRow,
      onRefresh: _refresh,
      onLoadMore: _loadMore,
      hasMore: _hasMore,
      totalCount: _total,
      isLoading: _loading || _loadingMore,
      qrExportPageBuilder: widget.qrExportPageBuilder,
    );
  }
}
