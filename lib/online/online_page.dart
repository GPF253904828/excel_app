// ignore_for_file: avoid_print

import 'dart:io';
import 'dart:math' as math;

import 'package:excel_app/device_detail_page.dart';
import 'package:excel_app/network_tools/xls_reader.dart';
import 'package:excel_app/online/online_config_page.dart';
import 'package:excel_app/online/online_config_store.dart';
import 'package:excel_app/qr/qr_create_page.dart';
import 'package:excel_app/spreadsheet_page.dart';
import 'package:excel_app/utils/net_util.dart';
import 'package:excel_app/utils/toast_util.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

/// 按业务优先级重排接口返回字段，不补充或映射不存在的列。
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

/// 按列表表头顺序重建详情数据，确保扫码详情与列表字段排列一致。
Map<String, dynamic> orderedOnlineDeviceData(
  Map<String, dynamic> data,
  List<String> headers,
) {
  return <String, dynamic>{
    for (final header in headers)
      if (data.containsKey(header)) header: data[header],
    for (final entry in data.entries)
      if (!headers.contains(entry.key)) entry.key: entry.value,
  };
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
  final bool showOnboardingGuide;
  final DeviceListCallback? onList;
  final DeviceModifyCallback? onModify;
  final DeviceAddCallback? onAdd;
  final DeviceDeleteCallback? onDelete;
  final QrExportPageBuilder? qrExportPageBuilder;
  final OnlineConfigStore configStore;
  final bool readOnly;

  const OnlinePage({
    super.key,
    this.showOnboardingGuide = true,
    this.onList,
    this.onModify,
    this.onAdd,
    this.onDelete,
    this.qrExportPageBuilder,
    this.configStore = const OnlineConfigStore(),
    this.readOnly = false,
  });

  @override
  State<OnlinePage> createState() => _OnlinePageState();
}

class _OnlinePageState extends State<OnlinePage> {
  static const int _pageSize = 100;
  static const _guideSeenCountKey = 'online_page_guide_seen_count';
  static const _guideMaxDisplays = 3;

  OnlineApiConfig? _apiConfig;
  XlsTable? _table;
  final List<Map<String, dynamic>> _rows = <Map<String, dynamic>>[];
  String? _error;
  bool _loading = true;
  bool _loadingMore = false;
  bool _loadingAll = false;
  bool _hasMore = false;
  int _nextStart = 0;
  int _loadedPageCount = 0;
  int? _total;
  String? _paginationStatus = '正在加载第一页';
  final _loadAllButtonKey = GlobalKey();
  final _refreshButtonKey = GlobalKey();
  final _configButtonKey = GlobalKey();
  final _guideHostKey = GlobalKey<_OnlinePageOverlayHostState>();
  bool _guideCheckScheduled = false;

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
      await _showOnboardingGuideIfNeeded();
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
    if (_loading || _loadingMore || _loadingAll) return;
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
  Future<void> _loadFirstPage() async {
    if (mounted) setState(() => _paginationStatus = '正在加载第一页');
    try {
      await _loadPage(start: 0, replace: true);
    } finally {
      if (mounted) setState(() => _paginationStatus = null);
    }
  }

  /// 首次列表加载完成后，按本地次数决定是否显示操作引导。
  Future<void> _showOnboardingGuideIfNeeded() async {
    if (!widget.showOnboardingGuide ||
        widget.readOnly ||
        _guideCheckScheduled ||
        !mounted) {
      return;
    }
    _guideCheckScheduled = true;
    try {
      final preferences = await SharedPreferences.getInstance();
      final seen = preferences.getInt(_guideSeenCountKey) ?? 0;
      if (seen >= _guideMaxDisplays || !mounted) return;
      await preferences.setInt(_guideSeenCountKey, seen + 1);
      if (!mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _presentOnboardingGuide();
      });
      WidgetsBinding.instance.scheduleFrame();
    } catch (error) {
      print('[Online][guide][error] $error');
    }
  }

  /// 将按钮的 RenderBox 坐标转换为 Overlay 使用的全局矩形。
  Rect? _globalRect(GlobalKey key) {
    final renderObject = key.currentContext?.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) return null;
    return renderObject.localToGlobal(Offset.zero) & renderObject.size;
  }

  /// 打开指向顶部三个操作按钮的模态引导层。
  void _presentOnboardingGuide() {
    final targets = <Rect?>[
      _globalRect(_loadAllButtonKey),
      _globalRect(_refreshButtonKey),
      _globalRect(_configButtonKey),
    ];
    if (targets.any((target) => target == null)) return;
    _guideHostKey.currentState?.showGuide(targets.cast<Rect>());
  }

  /// 在用户上拉到底部时追加下一页，不根据本页条数猜测是否结束。
  Future<void> _loadMore() async {
    if (_loading || _loadingMore || _loadingAll || !_hasMore) return;
    if (mounted) {
      setState(() => _paginationStatus = '正在加载第${_loadedPageCount + 1}页');
    }
    try {
      await _loadPage(start: _nextStart, replace: false);
    } catch (error) {
      if (mounted) ToastUtil.showCenter(_errorText(error));
    } finally {
      if (mounted) setState(() => _paginationStatus = null);
    }
  }

  /// 按接口返回的 nextStart 连续加载所有剩余分页。
  Future<void> _loadAll() async {
    if (_loading || _loadingMore || _loadingAll || !_hasMore) return;
    setState(() => _loadingAll = true);
    final requestedStarts = <int>{};
    try {
      while (_hasMore && mounted) {
        final start = _nextStart;
        if (!requestedStarts.add(start)) {
          throw DeviceApiException('分页位置未推进');
        }
        final page = _loadedPageCount + 1;
        setState(() => _paginationStatus = '正在加载第$page页');
        await _loadPage(start: start, replace: false);
      }
      if (mounted) setState(() => _paginationStatus = null);
    } catch (error) {
      print('[Online][load-all][error] $error');
      if (mounted) {
        setState(() => _paginationStatus = '加载失败: ${_errorText(error)}');
        ToastUtil.showCenter(_errorText(error));
      }
    } finally {
      if (mounted) setState(() => _loadingAll = false);
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
          _loadedPageCount = replace ? 1 : _loadedPageCount + 1;
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
    _loadedPageCount = 0;
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

  /// 将只读表格行转换为字段映射并打开设备详情页。
  Future<void> _openReadOnlyDetail(
    List<String> headers,
    List<String> row,
  ) async {
    final data = orderedOnlineDeviceData(<String, dynamic>{
      for (var index = 0; index < headers.length; index++)
        headers[index]: index < row.length ? row[index] : '',
    }, headers);
    await Navigator.push<void>(
      context,
      MaterialPageRoute(builder: (_) => DeviceDetailPage(data: data)),
    );
  }

  /// 将业务或传输异常转换为页面可读消息。
  String _errorText(Object error) {
    if (error is DeviceApiException) return error.message;
    return error.toString();
  }

  /// 创建在线表格使用的统一工具栏操作。
  List<Widget> _tableActions() => <Widget>[
        KeyedSubtree(
          key: _loadAllButtonKey,
          child: IconButton(
            key: const Key('online-load-all'),
            onPressed: _loading || _loadingMore || _loadingAll || !_hasMore
                ? null
                : _loadAll,
            tooltip: '自动加载全部',
            icon: const Icon(Icons.download_for_offline_outlined),
          ),
        ),
        KeyedSubtree(
          key: _refreshButtonKey,
          child: IconButton(
            key: const Key('online-refresh'),
            onPressed:
                _loading || _loadingMore || _loadingAll ? null : _refresh,
            tooltip: '刷新列表',
            icon: const Icon(Icons.refresh),
          ),
        ),
        if (!widget.readOnly)
          KeyedSubtree(
            key: _configButtonKey,
            child: IconButton(
              key: const Key('online-config'),
              onPressed:
                  _loading || _loadingMore || _loadingAll ? null : _openConfig,
              tooltip: '接口配置',
              icon: const Icon(Icons.settings_outlined),
            ),
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
                    Text('正在加载第一页'),
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
    return _OnlinePageOverlayHost(
      key: _guideHostKey,
      child: SpreadsheetPage(
        file: File('online_devices.xls'),
        table: table,
        title: '在线设备',
        appBarActions: _tableActions(),
        onSaveRow: widget.readOnly ? null : _saveRemoteRow,
        onDeleteRow: widget.readOnly ? null : _deleteRemoteRow,
        onRefresh: _refresh,
        onLoadMore: _loadMore,
        hasMore: _hasMore,
        totalCount: _total,
        paginationStatus: _paginationStatus,
        isLoading: _loading || _loadingMore || _loadingAll,
        readOnly: widget.readOnly,
        onViewRow: widget.readOnly ? _openReadOnlyDetail : null,
        qrExportPageBuilder: widget.qrExportPageBuilder,
      ),
    );
  }
}

/// 为在线设备页托管底层页面和可移除的模态引导层。
class _OnlinePageOverlayHost extends StatefulWidget {
  final Widget child;

  const _OnlinePageOverlayHost({
    super.key,
    required this.child,
  });

  @override
  State<_OnlinePageOverlayHost> createState() => _OnlinePageOverlayHostState();
}

class _OnlinePageOverlayHostState extends State<_OnlinePageOverlayHost> {
  final _overlayKey = GlobalKey<OverlayState>();
  late final OverlayEntry _contentEntry;
  OverlayEntry? _guideEntry;

  @override
  void initState() {
    super.initState();
    _contentEntry = OverlayEntry(builder: (_) => widget.child);
  }

  @override
  void didUpdateWidget(covariant _OnlinePageOverlayHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.child, widget.child)) {
      _contentEntry.markNeedsBuild();
    }
  }

  /// 在页面自己的 Overlay 上方显示操作引导。
  void showGuide(List<Rect> targets) {
    _guideEntry?.remove();
    final entry = OverlayEntry(
      builder: (_) => _OnlinePageGuide(
        targets: targets,
        onDismiss: dismissGuide,
      ),
    );
    _guideEntry = entry;
    _overlayKey.currentState?.insert(entry);
  }

  /// 移除当前操作引导层，恢复页面原有交互。
  void dismissGuide() {
    _guideEntry?.remove();
    _guideEntry = null;
  }

  @override
  void dispose() {
    _guideEntry?.remove();
    _contentEntry.remove();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Overlay(
        key: _overlayKey,
        initialEntries: <OverlayEntry>[_contentEntry],
      );
}

/// 展示在线设备页三个顶部操作的单层模态引导。
class _OnlinePageGuide extends StatelessWidget {
  final List<Rect> targets;
  final VoidCallback onDismiss;

  const _OnlinePageGuide({
    required this.targets,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: Material(
        key: const Key('online-page-guide'),
        color: Colors.transparent,
        child: LayoutBuilder(
          builder: (context, constraints) {
            const cardGap = 8.0;
            final cardWidth = (constraints.maxWidth - 32 - cardGap * 2) / 3;
            final cardTop = math.max(
              96.0,
              targets.map((target) => target.bottom).reduce(math.max) + 24,
            );
            final cardCenters = <Offset>[
              for (var index = 0; index < 3; index++)
                Offset(
                    16 + cardWidth * (index + .5) + cardGap * index, cardTop),
            ];
            return Stack(
              children: [
                const Positioned.fill(
                  child: ModalBarrier(
                    dismissible: false,
                    color: Colors.black54,
                    semanticsLabel: '在线设备操作引导',
                  ),
                ),
                Positioned.fill(
                  child: CustomPaint(
                    key: const Key('online-page-guide-arrows'),
                    painter: _GuideArrowPainter(
                      targets: targets,
                      starts: cardCenters,
                    ),
                  ),
                ),
                Positioned(
                  top: cardTop,
                  left: 16,
                  right: 16,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _card(
                        title: '加载全部',
                        description: '自动加载所有分页，不用再上拉加载更多。',
                        width: cardWidth,
                      ),
                      const SizedBox(width: cardGap),
                      _card(
                        title: '刷新',
                        description: '清空当前列表，重新加载第一页。',
                        width: cardWidth,
                      ),
                      const SizedBox(width: cardGap),
                      _card(
                        title: '接口配置',
                        description: '切换在线设备接口配置。',
                        width: cardWidth,
                      ),
                    ],
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 24,
                  child: SafeArea(
                    top: false,
                    child: Center(
                      child: FilledButton(
                        key: const Key('online-page-guide-dismiss'),
                        onPressed: onDismiss,
                        child: const Text('知道了'),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// 构建单个操作说明卡片，统一三列的尺寸和文字样式。
  Widget _card({
    required String title,
    required String description,
    required double width,
  }) =>
      SizedBox(
        width: width,
        child: Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.black87,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  description,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.black87,
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}

/// 在说明卡片和目标按钮之间绘制带箭头的引导线。
class _GuideArrowPainter extends CustomPainter {
  final List<Rect> targets;
  final List<Offset> starts;

  const _GuideArrowPainter({
    required this.targets,
    required this.starts,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;
    for (var index = 0; index < targets.length; index++) {
      final start = starts[index];
      final end = Offset(targets[index].center.dx, targets[index].bottom + 4);
      canvas.drawLine(start, end, linePaint);
      final direction = (end - start) / (end - start).distance;
      final side = Offset(-direction.dy, direction.dx);
      final base = end - direction * 12;
      canvas.drawLine(end, base + side * 5, linePaint);
      canvas.drawLine(end, base - side * 5, linePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _GuideArrowPainter oldDelegate) => true;
}
