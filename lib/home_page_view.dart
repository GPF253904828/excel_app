import 'package:flutter/material.dart';

/// 首页的纯展示层，只接收状态并转发用户操作。
class HomePageView extends StatelessWidget {
  final String status;
  final String? localIp;
  final int port;
  final bool isRunning;
  final bool hasFiles;
  final String? receivedNotice;
  final VoidCallback? onDeleteFiles;
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
    this.receivedNotice,
    this.onDeleteFiles,
  });

  /// 构建首页布局和文件服务操作按钮。
  @override
  Widget build(BuildContext context) {
    final address = 'http://$localIp:$port';
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('设备管理')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            '状态: $status',
            style: textTheme.titleMedium?.copyWith(
              color: colors.onSurface,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 16),
          if (localIp != null) ...[
            Text(
              '局域网地址:',
              style: textTheme.titleSmall?.copyWith(
                color: colors.onSurface,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            SelectableText(
              address,
              style: textTheme.titleLarge?.copyWith(
                color: colors.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              '在电脑浏览器中打开上面的地址即可上传文件',
              style: textTheme.bodyMedium?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
          ] else
            const Text('未获取到局域网 IP，请检查网络连接'),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ElevatedButton(
                onPressed: isRunning ? null : onStart,
                style: ElevatedButton.styleFrom(
                  backgroundColor: colors.primary,
                  foregroundColor: colors.onPrimary,
                ),
                child: const Text('启动服务'),
              ),
              const SizedBox(width: 16),
              ElevatedButton(
                onPressed: isRunning ? onStop : null,
                style: ElevatedButton.styleFrom(
                  foregroundColor: colors.onSurface,
                  side: BorderSide(color: colors.outline),
                  backgroundColor: colors.surface,
                ),
                child: const Text('停止服务'),
              ),
            ],
          ),
          const SizedBox(height: 40),
          SizedBox(
            width: 200,
            height: 60,
            child: ElevatedButton.icon(
              onPressed: hasFiles ? onOpenFiles : null,
              icon: const Icon(Icons.file_download),
              label: const Text('打开收到的文件'),
              style: ElevatedButton.styleFrom(
                backgroundColor: hasFiles ? colors.primary : null,
                foregroundColor: hasFiles ? colors.onPrimary : null,
              ),
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: 200,
            height: 48,
            child: OutlinedButton.icon(
              onPressed: hasFiles ? onDeleteFiles : null,
              icon: const Icon(Icons.delete_outline),
              label: const Text('删除本地文件'),
              style: OutlinedButton.styleFrom(
                foregroundColor: colors.onSurfaceVariant,
                side: BorderSide(color: colors.outline),
              ),
            ),
          ),
          if (receivedNotice != null) ...[
            const SizedBox(height: 12),
            Text(
              receivedNotice!,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: colors.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
