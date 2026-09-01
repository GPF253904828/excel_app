import 'package:excel_app/export_page.dart';
import 'package:excel_app/device_detail_page.dart';
import 'package:excel_app/home_page_controller.dart';
import 'package:excel_app/home_page_view.dart';
import 'package:excel_app/local_page.dart';
import 'package:excel_app/online/online_config_store.dart';
import 'package:excel_app/online/online_page.dart';
import 'package:excel_app/scanner_page.dart';
import 'package:excel_app/utils/net_util.dart';
import 'package:excel_app/utils/toast_util.dart';
import 'package:flutter/material.dart';

/// 定义可替换的线上设备查询，便于测试扫码后的实时数据流。
typedef OnlineDeviceQueryCallback = Future<DeviceResult> Function(
  String deviceNo,
  OnlineApiConfig config,
);

/// 移动端大厅，负责在线查看入口和本地文件服务状态。
class HomePage extends StatefulWidget {
  final OnlineConfigStore configStore;
  final OnlineDeviceQueryCallback? onQuery;
  final DeviceListCallback? onList;

  const HomePage({
    super.key,
    this.configStore = const OnlineConfigStore(),
    this.onQuery,
    this.onList,
  });

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late final HomePageController _controller;
  bool _onlineLoading = false;

  @override
  void initState() {
    super.initState();
    _controller = HomePageController();
    _controller.initialize();
  }

  /// 打开只读的在线设备列表。
  void _showOnlineList() {
    Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => OnlinePage(
          readOnly: true,
          configStore: widget.configStore,
          onList: widget.onList,
          qrExportPageBuilder: (archive, filename) => ExportPage(
            controller: _controller,
            archive: archive,
            filename: filename,
          ),
        ),
      ),
    );
  }

  /// 使用当前接口配置查询扫码设备的最新完整记录。
  Future<DeviceResult> _queryOnlineDevice(
    String deviceNo,
    OnlineApiConfig config,
  ) {
    final onQuery = widget.onQuery;
    if (onQuery != null) return onQuery(deviceNo, config);
    return DeviceApi.queryDevice(
      deviceNo,
      webhook: config.url,
      token: config.token,
    );
  }

  /// 扫码后查询线上最新数据，成功时打开只读详情页。
  Future<void> _scanOnlineDevice() async {
    final deviceNo = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const ScannerPage()),
    );
    if (deviceNo == null || !mounted) return;

    setState(() => _onlineLoading = true);
    try {
      final config = await widget.configStore.load();
      if (config == null) throw DeviceApiException('请先选择接口配置');
      final result = await _queryOnlineDevice(deviceNo, config);
      if (!result.success) {
        throw DeviceApiException(result.errorMessage ?? '未找到设备');
      }
      final data = result.data;
      if (data == null) throw DeviceApiException('接口未返回设备信息');
      if (!mounted) return;
      await Navigator.push<void>(
        context,
        MaterialPageRoute(builder: (_) => DeviceDetailPage(data: data)),
      );
    } catch (error) {
      if (mounted) ToastUtil.showCenter(_errorText(error));
    } finally {
      if (mounted) setState(() => _onlineLoading = false);
    }
  }

  /// 将接口异常转换为首页可展示的错误消息。
  String _errorText(Object error) =>
      error is DeviceApiException ? error.message : error.toString();

  /// 打开本地文件传输配置页面。
  void _showLocalPage() {
    Navigator.push<void>(
      context,
      MaterialPageRoute(builder: (_) => LocalPage(controller: _controller)),
    );
  }

  /// 释放首页拥有的共享文件服务控制器。
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// 构建大厅入口并转发导航操作。
  @override
  Widget build(BuildContext context) {
    return HomePageView(
      onOnlineScan: _scanOnlineDevice,
      onOnlineList: _showOnlineList,
      onLocalPage: _showLocalPage,
      isOnlineLoading: _onlineLoading,
    );
  }
}
