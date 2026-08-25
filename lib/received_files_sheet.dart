import 'dart:io';

import 'package:flutter/material.dart';

/// 显示已接收文件列表，并把用户选择的文件回传给首页。
class ReceivedFilesSheet extends StatelessWidget {
  final List<File> files;
  final Map<String, int> fileSizes;
  final Future<void> Function(File file) onFileSelected;

  const ReceivedFilesSheet({
    super.key,
    required this.files,
    required this.fileSizes,
    required this.onFileSelected,
  });

  /// 构建文件选择列表。
  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: files.length,
      itemBuilder: (context, index) {
        final file = files[index];
        final sizeKB = fileSizes[file.path] ?? 0;
        return ListTile(
          leading: const Icon(Icons.insert_drive_file),
          title: Text(file.uri.pathSegments.last),
          subtitle: Text('$sizeKB KB'),
          onTap: () async {
            Navigator.pop(context);
            await onFileSelected(file);
          },
        );
      },
    );
  }
}

/// 打开已接收文件选择弹层。
Future<void> showReceivedFilesSheet(
  BuildContext context, {
  required List<File> files,
  required Future<void> Function(File file) onFileSelected,
}) async {
  final fileSizes = <String, int>{};
  for (final file in files) {
    fileSizes[file.path] = file.lengthSync() ~/ 1024;
  }

  await showModalBottomSheet<void>(
    context: context,
    builder: (_) => ReceivedFilesSheet(
      files: files,
      fileSizes: fileSizes,
      onFileSelected: onFileSelected,
    ),
  );
}
