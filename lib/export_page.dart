import 'dart:typed_data';

import 'package:excel_app/home_page_controller.dart';
import 'package:excel_app/local_page_view.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

/// 将二维码 ZIP 交给系统分享面板或测试替身。
typedef QrArchiveShareCallback = Future<void> Function(
  Uint8List archive,
  String filename,
);

/// 在局域网服务启动后向电脑导出已生成的二维码 ZIP。
class ExportPage extends StatefulWidget {
  final HomePageController controller;
  final Uint8List archive;
  final String filename;
  final QrArchiveShareCallback? onShare;

  const ExportPage({
    super.key,
    required this.controller,
    required this.archive,
    required this.filename,
    this.onShare,
  });

  @override
  State<ExportPage> createState() => _ExportPageState();
}

class _ExportPageState extends State<ExportPage> {
  bool _starting = true;
  bool _exporting = false;
  bool _sharing = false;
  String? _notice;
  final _shareButtonKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _startServer();
  }

  /// 进入导出页时自动启动文件服务。
  Future<void> _startServer() async {
    try {
      await widget.controller.startServer();
      if (mounted && !widget.controller.isRunning) {
        setState(() => _notice = '启动失败: ${widget.controller.status}');
      }
    } catch (error) {
      if (mounted) setState(() => _notice = '启动失败: $error');
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  /// 启动服务后将二维码 ZIP 排队给电脑浏览器下载。
  Future<void> _exportQrArchive() async {
    if (_starting || _exporting) return;
    setState(() {
      _exporting = true;
      _notice = null;
    });
    try {
      await widget.controller.startServer();
      if (!widget.controller.isRunning) {
        throw StateError(widget.controller.status);
      }
      await widget.controller.exportQrArchive(widget.archive, widget.filename);
      if (mounted) setState(() => _notice = '已准备 ${widget.filename}');
    } catch (error) {
      if (mounted) setState(() => _notice = '导出失败: $error');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  /// 使用 share_plus 分享当前二维码 ZIP，并反馈分享结果。
  Future<void> _shareQrArchive() async {
    if (_starting || _exporting || _sharing) return;
    setState(() {
      _sharing = true;
      _notice = null;
    });
    try {
      final onShare = widget.onShare;
      if (onShare != null) {
        await onShare(widget.archive, widget.filename);
      } else {
        final renderBox =
            _shareButtonKey.currentContext?.findRenderObject() as RenderBox?;
        await Share.shareXFiles(
          <XFile>[
            XFile.fromData(
              widget.archive,
              name: widget.filename,
              mimeType: 'application/zip',
            ),
          ],
          subject: '二维码导出',
          sharePositionOrigin: renderBox == null
              ? null
              : renderBox.localToGlobal(Offset.zero) & renderBox.size,
        );
      }
      if (mounted) setState(() => _notice = '已分享 ${widget.filename}');
    } catch (error) {
      if (mounted) setState(() => _notice = '分享失败: $error');
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  /// 构建服务状态、局域网地址和二维码导出操作。
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) => LocalPageView(
        title: '导出二维码',
        status: widget.controller.status,
        localIp: widget.controller.localIp,
        networkInfo: widget.controller.networkInfo,
        port: widget.controller.port,
        isRunning: widget.controller.isRunning,
        hasFiles: false,
        pendingExportFilename:
            widget.controller.pendingExportFilename ?? widget.filename,
        networkHint: '在电脑浏览器中打开上面的地址即可接收导出文件',
        showFileManagement: false,
        onStart: () => widget.controller.startServer(),
        onStop: widget.controller.stopServer,
        onOpenFiles: () {},
        extraAction: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    key: const Key('export-qr-archive'),
                    onPressed: _starting || _exporting || _sharing
                        ? null
                        : _exportQrArchive,
                    icon: _starting || _exporting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.file_upload_outlined),
                    label: Text(_starting
                        ? '启动服务中...'
                        : (_exporting ? '处理中...' : '导出二维码')),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: KeyedSubtree(
                    key: const Key('share-qr-archive'),
                    child: OutlinedButton.icon(
                      key: _shareButtonKey,
                      onPressed: _starting || _exporting || _sharing
                          ? null
                          : _shareQrArchive,
                      icon: _sharing
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.share_outlined),
                      label: Text(_sharing ? '分享中...' : '分享'),
                    ),
                  ),
                ),
              ],
            ),
            if (_notice != null) ...[
              const SizedBox(height: 8),
              Text(
                _notice!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _notice!.contains('失败')
                      ? Theme.of(context).colorScheme.error
                      : Theme.of(context).colorScheme.primary,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
