import 'dart:io';

import 'package:excel_app/home_page_controller.dart';
import 'package:excel_app/local_page_view.dart';
import 'package:excel_app/network_tools/xls_reader.dart';
import 'package:excel_app/received_files_sheet.dart';
import 'package:excel_app/spreadsheet_page.dart';
import 'package:excel_app/utils/toast_util.dart';
import 'package:flutter/material.dart';

/// 移动端本地文件传输配置页，负责组合控制器、视图和文件操作。
class LocalPage extends StatefulWidget {
  const LocalPage({super.key});

  @override
  State<LocalPage> createState() => _LocalPageState();
}

class _LocalPageState extends State<LocalPage> {
  late final HomePageController _controller;

  @override
  void initState() {
    super.initState();
    _controller = HomePageController();
    _controller.onConfirmReplace = _confirmReplace;
    _controller.initialize();
  }

  /// 新文件到达且本地已有文件时，确认是否替换旧文件。
  Future<bool> _confirmReplace(List<String> filenames) async {
    if (!mounted) return false;
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('收到新文件'),
        content: Text(
          '已收到 ${filenames.join('、')} 文件，是否要替换本地已经存在的文件？',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('保留本地文件'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('确认替换'),
          ),
        ],
      ),
    );
    return result == true;
  }

  /// 二次确认后删除手机本地保存的接收文件。
  Future<void> _deleteReceivedFiles() async {
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除本地文件'),
        content: const Text('确定删除手机本地保存的所有表格文件吗？此操作不可恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed == true) await _controller.deleteReceivedFiles();
  }

  /// 打开已接收文件列表。
  Future<void> _onImport() async {
    final files = _controller.receivedFiles;
    if (files.isEmpty) {
      _controller.refreshFiles();
      return;
    }

    if (files.length == 1) {
      await _showSpreadsheet(files.single);
      return;
    }

    await showReceivedFilesSheet(
      context,
      files: files,
      onFileSelected: _showSpreadsheet,
    );
  }

  /// 读取 XLS 文件并跳转到全屏表格页面。
  Future<void> _showSpreadsheet(File file) async {
    try {
      final table = XlsReader().read(await file.readAsBytes());
      if (!mounted) return;
      if (table.headers.isEmpty) {
        ToastUtil.showCenter('Excel 文件没有可展示的数据');
        return;
      }

      await Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => SpreadsheetPage(
            file: file,
            table: table,
            onSave: (editedTable) =>
                _controller.exportEditedFile(file, editedTable),
            onExportQrCodes: (bytes, filename) =>
                _controller.exportQrArchive(bytes, filename),
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ToastUtil.showCenter('Excel 文件读取失败: $error');
    }
  }

  /// 释放本地页控制器及文件服务。
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// 构建由控制器驱动的本地配置视图。
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return LocalPageView(
          status: _controller.status,
          localIp: _controller.localIp,
          port: _controller.port,
          isRunning: _controller.isRunning,
          hasFiles: _controller.hasFiles,
          receivedNotice: _controller.receivedNotice,
          onDeleteFiles: _deleteReceivedFiles,
          onStart: () => _controller.startServer(),
          onStop: _controller.stopServer,
          onOpenFiles: _onImport,
        );
      },
    );
  }
}
