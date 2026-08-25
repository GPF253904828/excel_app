import 'dart:io';

import 'package:excel_app/home_page_controller.dart';
import 'package:excel_app/home_page_view.dart';
import 'package:excel_app/network_tools/xls_reader.dart';
import 'package:excel_app/received_files_sheet.dart';
import 'package:excel_app/spreadsheet_page.dart';
import 'package:flutter/material.dart';

/// 手机端文件接收首页，负责组合控制器、视图和页面跳转。
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

  /// 打开已接收文件列表。
  Future<void> _onImport() async {
    final files = _controller.receivedFiles;
    if (files.isEmpty) {
      _controller.refreshFiles();
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Excel 文件没有可展示的数据')),
        );
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
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Excel 文件读取失败: $error')),
      );
    }
  }

  /// 释放首页控制器及文件服务。
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// 构建由控制器驱动的首页视图。
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return HomePageView(
          status: _controller.status,
          localIp: _controller.localIp,
          port: _controller.port,
          isRunning: _controller.isRunning,
          hasFiles: _controller.hasFiles,
          onStart: () => _controller.startServer(),
          onStop: _controller.stopServer,
          onOpenFiles: _onImport,
        );
      },
    );
  }
}
