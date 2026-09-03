import 'dart:io';

import 'package:excel_app/log/app_log.dart';
import 'package:flutter/material.dart';

/// 定义诊断日志上传回调，具体上传地址由业务层注入。
typedef LogUploadCallback = Future<void> Function(File file);

/// 定义生成并调起系统分享面板的回调。
typedef LogShareCallback = Future<File> Function();

/// 展示日志摘要，并提供上传入口；邮件发送保留为待接入状态。
class LogDiagnosticsPage extends StatefulWidget {
  final LogUploadCallback? onUpload;
  final LogShareCallback? onShare;
  final LogUploadCallback? onEmail;

  const LogDiagnosticsPage(
      {super.key, this.onUpload, this.onShare, this.onEmail});

  @override
  State<LogDiagnosticsPage> createState() => _LogDiagnosticsPageState();
}

class _LogDiagnosticsPageState extends State<LogDiagnosticsPage> {
  String _content = '';
  String? _path;
  String? _logFileSize;
  bool _loading = true;
  bool _uploading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// 读取日志文件和路径，供用户确认诊断信息是否已生成。
  Future<void> _load() async {
    final content = await AppLog.read();
    final path = await AppLog.filePath;
    final logFileSize = await AppLog.logFileSizeString;
    if (!mounted) return;
    setState(() {
      _content = content;
      _path = path;
      _loading = false;
      _logFileSize = logFileSize;
    });
  }

  /// 调用业务层上传回调，未接入时明确提示日志仍保存在本机。
  Future<void> _upload() async {
    final share = widget.onShare;
    if (share != null) {
      setState(() => _uploading = true);
      try {
        await share();
        _showMessage('已打开系统分享面板');
      } catch (error) {
        _showMessage('分享日志失败：$error');
      } finally {
        if (mounted) setState(() => _uploading = false);
      }
      return;
    }
    final callback = widget.onUpload;
    final path = _path;
    if (callback == null || path == null) {
      _showMessage('日志已保存到本机，分享功能待接入');
      return;
    }
    setState(() => _uploading = true);
    try {
      await callback(File(path));
      _showMessage('日志上传成功');
    } catch (error) {
      _showMessage('日志上传失败：$error');
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  void _showMessage(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('诊断日志')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(_path ?? '日志尚未初始化'),
                  Text(_logFileSize ?? '日志文件大小未知'),
                  const SizedBox(height: 12),
                  // Expanded(
                  //   child: SelectableText(
                  //     _content.isEmpty ? '暂无日志' : _content,
                  //     key: const Key('diagnostic-log-content'),
                  //   ),
                  // ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _uploading ? null : _upload,
                    icon: _uploading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.upload_file),
                    label: Text(_uploading ? '处理中...' : '分享日志 ZIP'),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
    );
  }
}
