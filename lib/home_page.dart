import 'package:excel_app/local_page.dart';
import 'package:excel_app/online/online_page.dart';
import 'package:excel_app/home_page_view.dart';
import 'package:flutter/material.dart';

/// 移动端大厅，负责连接在线和本地两个业务入口。
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  /// 打开在线设备管理页面。
  void _showOnlinePage(BuildContext context) {
    Navigator.push<void>(
      context,
      MaterialPageRoute(builder: (_) => const OnlinePage()),
    );
  }

  /// 打开本地文件传输配置页面。
  void _showLocalPage(BuildContext context) {
    Navigator.push<void>(
      context,
      MaterialPageRoute(builder: (_) => const LocalPage()),
    );
  }

  /// 构建大厅视图并连接两个导航回调。
  @override
  Widget build(BuildContext context) {
    return HomePageView(
      onOnlinePage: () => _showOnlinePage(context),
      onLocalPage: () => _showLocalPage(context),
    );
  }
}
