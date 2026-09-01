import 'package:flutter/material.dart';

/// 展示一条设备记录的只读字段和值。
class DeviceDetailPage extends StatelessWidget {
  final Map<String, dynamic> data;

  const DeviceDetailPage({super.key, required this.data});

  /// 构建可滚动的设备详情字段列表。
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('设备详情')),
      body: ListView.separated(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        itemCount: data.length,
        separatorBuilder: (_, __) => Divider(color: colors.outlineVariant),
        itemBuilder: (context, index) {
          final entry = data.entries.elementAt(index);
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              key: Key('detail-field-${entry.key}'),
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 100,
                  child: Text(
                    entry.key,
                    style: TextStyle(
                      color: colors.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(child: Text(entry.value?.toString() ?? '')),
              ],
            ),
          );
        },
      ),
    );
  }
}
