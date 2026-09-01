import 'package:flutter/material.dart';

/// 首页大厅的纯展示层，只负责转发在线和本地入口操作。
class HomePageView extends StatelessWidget {
  final VoidCallback onOnlineScan;
  final VoidCallback onOnlineList;
  final VoidCallback onLocalPage;
  final bool isOnlineLoading;

  const HomePageView({
    super.key,
    required this.onOnlineScan,
    required this.onOnlineList,
    required this.onLocalPage,
    this.isOnlineLoading = false,
  });

  /// 构建大厅布局和两个业务入口。
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('大厅')),
      body: Stack(
        children: [
          Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 240,
                    height: 64,
                    child: FilledButton.icon(
                      onPressed: isOnlineLoading ? null : onOnlineScan,
                      icon: const Icon(Icons.qr_code_scanner_outlined),
                      label: const Text('扫码'),
                    ),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: 240,
                    height: 64,
                    child: OutlinedButton.icon(
                      onPressed: isOnlineLoading ? null : onOnlineList,
                      icon: const Icon(Icons.cloud_outlined),
                      label: const Text('全部'),
                    ),
                  ),
                  const SizedBox(height: 200),
                  // SizedBox(
                  //   width: 240,
                  //   height: 64,
                  //   child: OutlinedButton.icon(
                  //     onPressed: isOnlineLoading ? null : onLocalPage,
                  //     icon: const Icon(Icons.folder_outlined),
                  //     label: const Text('本地'),
                  //   ),
                  // ),
                ],
              ),
            ),
          ),
          if (isOnlineLoading)
            Positioned.fill(
              child: Container(
                color: const Color(0xCCFFFFFF),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      CircularProgressIndicator(),
                      SizedBox(height: 12),
                      Text('正在获取数据...'),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
