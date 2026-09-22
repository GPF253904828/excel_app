import 'dart:io';
import 'dart:typed_data';

import 'package:excel_app/qr/qr_code_service.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

/// 使用已生成的二维码 ZIP 构建二级导出页面。
typedef QrExportPageBuilder = Widget Function(
  Uint8List archive,
  String filename,
);

/// 提供设备二维码的选择、生成和导出操作。
class QrTestPage extends StatefulWidget {
  const QrTestPage({super.key});

  @override
  State<QrTestPage> createState() => _QrTestPageState();
}

class _QrTestPageState extends State<QrTestPage> {
  late final Future<void> _initialCleanup;
  List<File>? _generatedFiles;
  late List<QrDevice> _generatedDevices;
  String _status = '';
  bool _busy = false;
  bool _generationQueued = false;
  QrCodeService? service;

  @override
  void initState() {
    super.initState();
    _generateService();
    _generatedDevices = [
      const QrDevice('ACCB-N-1013', 'DynaMagTM-96 Side磁力架', '7300Plus'),
      const QrDevice('ACCB-N-1013-1', '磁力架变送器这哪', '/'),
      const QrDevice(
          'ACCB-N-1157', 'Agilent 2100 Bioanalyzer system', '2-20μL'),
// 荧光定量PCR仪器（4号）
// 卧式冷藏冷冻转换柜(-20）
// 海尔卧式转换冷冻展示柜
// GPRS温度记录变送器
// NanoDrop微量分光光度计
// Bench Smart 96移液工作站
// HERAEUS台式高速离心机
// NanoDrop微量分光光度计
// DynaMagTM-96 Side磁力架
// NanoDrop微量分光光度计
// Agilent 2100 Bioanalyzer system
// 手提式压力蒸汽灭菌器
    ];
    _initialCleanup = _clearExistingQrFiles();

    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) _generate();
    });
  }

  _generateService() async {
    final appDirectory = await getApplicationDocumentsDirectory();
    service = QrCodeService(Directory('${appDirectory.path}/二维码合计'));
  }

  /// 页面打开时优先清理上次生成的二维码，避免旧文件被误导出。
  Future<void> _clearExistingQrFiles() async {
    setState(() {
      _busy = true;
      _status = '正在清理旧二维码';
    });
    try {
      await service!.clear();
      if (!mounted) return;
      setState(() => _status = '');
    } catch (error) {
      if (!mounted) return;
      setState(() => _status = '失败: $error');
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  /// 生成当前选中设备的二维码图片。
  Future<void> _generate() async {
    if (_generationQueued) return;
    _generationQueued = true;
    await _initialCleanup;
    _generationQueued = false;
    if (!mounted || _busy) return;

    final devices = _generatedDevices;
    if (devices.isEmpty) {
      setState(() => _status = '请至少选择一条设备数据');
      return;
    }

    setState(() {
      _busy = true;
      _status = '生成中';
      _generatedFiles = null;
    });
    try {
      final files = await service?.generate(devices);
      if (!mounted) return;
      setState(() {
        _generatedFiles = files;
        _generatedDevices = devices;
        _status = '生成已完成';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _status = '失败: $error');
    } finally {
      if (mounted) setState(() => _busy = false);

      WidgetsBinding.instance.addPostFrameCallback((_) {
        final device = _generatedDevices[0];
        final file = _fileForDevice(device);
        _preview(device, file!);
      });
    }
  }

  /// 根据设备记录找到最近一次生成的图片文件。
  File? _fileForDevice(QrDevice device) {
    final files = _generatedFiles;
    final devices = _generatedDevices;
    if (files == null) return null;
    final index = devices.indexOf(device);
    return index >= 0 && index < files.length ? files[index] : null;
  }

  /// 打开二维码大图预览，生成文件不存在时不触发无效图片加载。
  Future<void> _preview(QrDevice device, File file) async {
    if (!file.existsSync() || !mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        child: Padding(
          padding: const EdgeInsets.all(0),
          child: InteractiveViewer(
            // minScale: .8,
            // maxScale: 4,
            child: Image.file(file, fit: BoxFit.contain),
          ),
        ),
      ),
    );
  }

  /// 构建二维码缩略图；只有生成成功且文件存在时才显示图片。
  Widget _thumbnail(File file) {
    return Container(
      width: 54,
      height: 54,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceVariant,
        borderRadius: BorderRadius.circular(10),
      ),
      clipBehavior: Clip.antiAlias,
      child: Image.file(file, fit: BoxFit.cover),
    );
  }

  /// 构建设备选择列表、缩略图和生成/导出操作按钮。
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('生成二维码')),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView.builder(
                itemCount: _generatedDevices.length,
                itemBuilder: (context, index) {
                  final device = _generatedDevices[index];
                  final file = _fileForDevice(device);
                  return Card(
                    margin: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 4,
                    ),
                    child: ListTile(
                      // leading: Checkbox(
                      //   key: Key('device-checkbox-$index'),
                      //   value: _selected[index],
                      //   onChanged: _busy
                      //       ? null
                      //       : (value) => _changeSelection(
                      //             index,
                      //             value ?? false,
                      //           ),
                      // ),
                      title: Text(device.deviceNumber),
                      subtitle: Text(device.deviceName),
                      trailing: file == null || !file.existsSync()
                          ? null
                          : Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _thumbnail(file),
                                const SizedBox(width: 8),
                                Icon(
                                  Icons.open_in_full,
                                  size: 18,
                                  color: colors.onSurfaceVariant,
                                ),
                              ],
                            ),
                      onTap: file == null ? null : () => _preview(device, file),
                    ),
                  );
                },
              ),
            ),
            if (_status.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  _status,
                  style: TextStyle(
                    color: _status.startsWith('失败')
                        ? colors.error
                        : colors.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  FilledButton.icon(
                    onPressed: _busy ? null : _generate,
                    icon: const Icon(Icons.qr_code),
                    label: const Text('生成'),
                  ),
                  const SizedBox(width: 12),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
