import 'package:flutter/material.dart';

/// 首页大厅的纯展示层，只负责转发在线和本地入口操作。
class HomePageView extends StatelessWidget {
  final VoidCallback onOnlinePage;
  final VoidCallback onLocalPage;
  final VoidCallback onExportPage;

  const HomePageView({
    super.key,
    required this.onOnlinePage,
    required this.onLocalPage,
    required this.onExportPage,
  });

  /// 构建大厅布局和两个业务入口。
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('大厅')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 240,
                height: 64,
                child: FilledButton.icon(
                  onPressed: onOnlinePage,
                  icon: const Icon(Icons.cloud_outlined),
                  label: const Text('在线'),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: 240,
                height: 64,
                child: OutlinedButton.icon(
                  onPressed: onLocalPage,
                  icon: const Icon(Icons.folder_outlined),
                  label: const Text('本地'),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: 240,
                height: 64,
                child: OutlinedButton.icon(
                  onPressed: onExportPage,
                  icon: const Icon(Icons.file_upload_outlined),
                  label: const Text('导出'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
