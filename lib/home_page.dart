import 'package:excel_app/export_page.dart';
import 'package:excel_app/home_page_controller.dart';
import 'package:excel_app/home_page_view.dart';
import 'package:excel_app/local_page.dart';
import 'package:excel_app/online/online_page.dart';
import 'package:flutter/material.dart';

/// 移动端大厅，负责共享在线和本地二维码导出服务状态。
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late final HomePageController _controller;

  @override
  void initState() {
    super.initState();
    _controller = HomePageController();
    _controller.initialize();
  }

  /// 打开在线设备列表，并共享二维码导出页面构造器。
  void _showOnlinePage() {
    Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => OnlinePage(
          qrExportPageBuilder: (archive, filename) => ExportPage(
            controller: _controller,
            archive: archive,
            filename: filename,
          ),
        ),
      ),
    );
  }

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
      onOnlinePage: _showOnlinePage,
      onLocalPage: _showLocalPage,
    );
  }
}
