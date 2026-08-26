import 'dart:io';

import 'package:excel_app/network_tools/csv_exporter.dart';
import 'package:excel_app/network_tools/file_service.dart';
import 'package:excel_app/network_tools/xls_reader.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// 管理首页的文件服务生命周期和已接收文件状态。
class HomePageController extends ChangeNotifier {
  final int port;
  FileServer? _fileServer;
  Directory? _saveDir;
  String? _localIp;
  String _status = '未启动';
  String? _receivedNotice;
  bool _hasFiles = false;
  bool _disposed = false;

  /// 接收新文件且本地已有文件时，由页面提供替换确认弹窗。
  Future<bool> Function(List<String> filenames)? onConfirmReplace;

  HomePageController({this.port = 8080});

  String? get localIp => _localIp;
  String get status => _status;
  bool get isRunning => _fileServer != null;
  bool get hasFiles => _hasFiles;
  String? get receivedNotice => _receivedNotice;

  /// 返回当前保存目录中可以展示的文件。
  List<File> get receivedFiles {
    final dir = _saveDir;
    if (dir == null || !dir.existsSync()) return [];
    return dir
        .listSync()
        .whereType<File>()
        .where((file) => !file.path.endsWith('.tmp'))
        .toList();
  }

  /// 初始化持久化目录并启动局域网文件服务。
  Future<void> initialize() async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      if (_disposed) return;

      _saveDir = Directory('${appDir.path}/received')
        ..createSync(recursive: true);
      refreshFiles();
      await startServer();
    } catch (error) {
      _status = '启动失败: $error';
      _notifyListeners();
    }
  }

  /// 重新扫描保存目录并更新按钮状态。
  void refreshFiles() {
    _hasFiles = receivedFiles.isNotEmpty;
    _notifyListeners();
  }

  /// 删除本地接收目录中的所有文件，并刷新首页状态。
  Future<void> deleteReceivedFiles() async {
    for (final file in receivedFiles) {
      await file.delete();
    }
    _receivedNotice = null;
    refreshFiles();
  }

  /// 启动文件服务。
  Future<void> startServer() async {
    if (_fileServer != null || _saveDir == null || _disposed) return;

    try {
      _localIp = await getLocalIp();
      if (_disposed) return;

      final server = FileServer(port: port, saveDir: _saveDir!);
      server.onFilesReceived = _onFilesReceived;
      server.onReplaceExistingFiles = onConfirmReplace;
      _fileServer = server;
      _status = '运行中';
      _notifyListeners();

      // FileServer.init() 持续监听请求，直到 release() 关闭服务。
      server.init();
    } catch (error) {
      _status = '启动失败: $error';
      _notifyListeners();
    }
  }

  /// 导出编辑后的表格并排队等待电脑页面下载。
  Future<void> exportEditedFile(File originalFile, XlsTable table) async {
    final server = _fileServer;
    if (server == null) {
      throw StateError('文件服务未启动');
    }

    final originalName = originalFile.uri.pathSegments.last;
    final dot = originalName.lastIndexOf('.');
    final baseName = dot > 0 ? originalName.substring(0, dot) : originalName;
    const extension = '.csv';
    final now = DateTime.now();
    final timestamp = '${now.year.toString().padLeft(4, '0')}'
        '${now.month.toString().padLeft(2, '0')}'
        '${now.day.toString().padLeft(2, '0')}_'
        '${now.hour.toString().padLeft(2, '0')}'
        '${now.minute.toString().padLeft(2, '0')}'
        '${now.second.toString().padLeft(2, '0')}';
    final filename = '${baseName}_edited_$timestamp$extension';
    server.queueExport(CsvExporter().export(table), filename);
  }

  /// 将二维码 ZIP 排队，等待电脑端页面下载到默认目录。
  Future<void> exportQrArchive(Uint8List bytes, String filename) async {
    final server = _fileServer;
    if (server == null) {
      throw StateError('文件服务未启动');
    }
    server.queueExport(
      bytes,
      filename,
      contentType: 'application/zip',
    );
  }

  /// 停止文件服务并更新首页状态。
  void stopServer() {
    _fileServer?.release();
    _fileServer = null;
    _status = '已停止';
    _notifyListeners();
  }

  /// 接收服务通知后刷新"打开收到的文件"按钮。
  void _onFilesReceived(Directory dir) {
    if (_disposed) return;
    _saveDir = dir;
    final names =
        receivedFiles.map((file) => file.uri.pathSegments.last).toList();
    final now = DateTime.now();
    final timestamp =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} '
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
    _receivedNotice = '$timestamp 已收到 ${names.join('、')} 文件';
    refreshFiles();
  }

  /// 在控制器销毁时释放文件服务和监听资源。
  @override
  void dispose() {
    _disposed = true;
    _fileServer?.release();
    _fileServer = null;
    super.dispose();
  }

  /// 在控制器仍有效时通知首页重新构建。
  void _notifyListeners() {
    if (!_disposed) notifyListeners();
  }
}
