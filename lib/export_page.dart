import 'package:excel_app/home_page_controller.dart';
import 'package:excel_app/local_page_view.dart';
import 'package:flutter/material.dart';

/// 展示用于向电脑导出文件的共享局域网服务。
class ExportPage extends StatelessWidget {
  final HomePageController controller;

  const ExportPage({super.key, required this.controller});

  /// 构建共享服务的状态、地址和待下载文件信息。
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) => LocalPageView(
        title: '导出',
        status: controller.status,
        localIp: controller.localIp,
        port: controller.port,
        isRunning: controller.isRunning,
        hasFiles: false,
        pendingExportFilename: controller.pendingExportFilename,
        networkHint: '在电脑浏览器中打开上面的地址即可接收导出文件',
        showFileManagement: false,
        onStart: () => controller.startServer(),
        onStop: controller.stopServer,
        onOpenFiles: () {},
      ),
    );
  }
}
