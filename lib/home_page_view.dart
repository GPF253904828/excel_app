import 'package:flutter/material.dart';

/// 首页的纯展示层，只接收状态并转发用户操作。
class HomePageView extends StatelessWidget {
  final String status;
  final String? localIp;
  final int port;
  final bool isRunning;
  final bool hasFiles;
  final VoidCallback onStart;
  final VoidCallback onStop;
  final VoidCallback onOpenFiles;

  const HomePageView({
    super.key,
    required this.status,
    required this.localIp,
    required this.port,
    required this.isRunning,
    required this.hasFiles,
    required this.onStart,
    required this.onStop,
    required this.onOpenFiles,
  });

  /// 构建首页布局和文件服务操作按钮。
  @override
  Widget build(BuildContext context) {
    final address = 'http://$localIp:$port';

    return Scaffold(
      appBar: AppBar(title: const Text('文件接收器')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text('状态: $status', style: const TextStyle(fontSize: 18)),
            const SizedBox(height: 16),
            if (localIp != null) ...[
              const Text('局域网地址:',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              SelectableText(address,
                  style: const TextStyle(fontSize: 20, color: Colors.blue)),
              const SizedBox(height: 8),
              const Text('在电脑浏览器中打开上面的地址即可上传文件',
                  style: TextStyle(color: Colors.grey)),
            ] else
              const Text('未获取到局域网 IP，请检查网络连接'),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton(
                  onPressed: isRunning ? null : onStart,
                  child: const Text('启动服务'),
                ),
                const SizedBox(width: 16),
                ElevatedButton(
                  onPressed: isRunning ? onStop : null,
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                  child: const Text('停止服务'),
                ),
              ],
            ),
            const Spacer(),
            SizedBox(
              width: 200,
              height: 60,
              child: ElevatedButton.icon(
                onPressed: hasFiles ? onOpenFiles : null,
                icon: const Icon(Icons.file_download),
                label: const Text('打开收到的文件'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: hasFiles ? Colors.green : null,
                  foregroundColor: hasFiles ? Colors.white : null,
                ),
              ),
            ),
            const Spacer(),
          ],
        ),
      ),
    );
  }
}
