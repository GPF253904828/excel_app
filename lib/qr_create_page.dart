import 'dart:io';
import 'dart:typed_data';

import 'package:excel_app/qr_code_service.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

/// 使用已生成的二维码 ZIP 构建二级导出页面。
typedef QrExportPageBuilder = Widget Function(
  Uint8List archive,
  String filename,
);

/// 提供设备二维码的选择、生成和导出操作。
class QrCreatePage extends StatefulWidget {
  final List<String> headers;
  final List<List<String>> rows;
  final QrCodeService? service;
  final Future<void> Function(Uint8List bytes, String filename)? onExport;
  final QrExportPageBuilder? exportPageBuilder;

  const QrCreatePage({
    super.key,
    required this.headers,
    required this.rows,
    this.service,
    this.onExport,
    this.exportPageBuilder,
  });

  @override
  State<QrCreatePage> createState() => _QrCreatePageState();
}

class _QrCreatePageState extends State<QrCreatePage> {
  late final List<QrDevice> _devices;
  late final List<bool> _selected;
  late final Future<void> _initialCleanup;
  List<File>? _generatedFiles;
  List<QrDevice>? _generatedDevices;
  String _status = '';
  bool _busy = false;
  bool _initialCleanupPending = true;
  bool _generationQueued = false;

  @override
  void initState() {
    super.initState();
    _devices = extractQrDevices(widget.headers, widget.rows);
    _selected = List<bool>.filled(_devices.length, true);
    _initialCleanup = _clearExistingQrFiles();
  }

  /// 返回当前选中的设备记录。
  List<QrDevice> get _selectedDevices => [
        for (var i = 0; i < _devices.length; i++)
          if (_selected[i]) _devices[i],
      ];

  /// 判断表格是否包含二维码所需的两个字段。
  bool get _hasRequiredHeaders =>
      widget.headers.contains('设备编号') && widget.headers.contains('设备名称');

  /// 返回顶部全选框需要显示的三态值。
  bool? get _selectAllValue {
    if (_selected.isEmpty || _selected.every((value) => !value)) return false;
    if (_selected.every((value) => value)) return true;
    return null;
  }

  /// 修改单条设备的选中状态并使上一次生成结果失效。
  void _changeSelection(int index, bool selected) {
    if (_busy) return;
    setState(() {
      _selected[index] = selected;
      _generatedFiles = null;
      _generatedDevices = null;
      _status = '请选择设备后重新生成';
    });
  }

  /// 全选或取消选择所有有效设备。
  void _changeAll(bool selected) {
    if (_busy) return;
    setState(() {
      for (var i = 0; i < _selected.length; i++) {
        _selected[i] = selected;
      }
      _generatedFiles = null;
      _generatedDevices = null;
      _status = '请选择设备后重新生成';
    });
  }

  /// 获取默认应用目录中的二维码输出服务。
  Future<QrCodeService> _getService() async {
    final service = widget.service;
    if (service != null) return service;
    final appDirectory = await getApplicationDocumentsDirectory();
    return QrCodeService(Directory('${appDirectory.path}/二维码合计'));
  }

  /// 页面打开时优先清理上次生成的二维码，避免旧文件被误导出。
  Future<void> _clearExistingQrFiles() async {
    setState(() {
      _busy = true;
      _status = '正在清理旧二维码';
    });
    try {
      await (await _getService()).clear();
      if (!mounted) return;
      setState(() => _status = '');
    } catch (error) {
      if (!mounted) return;
      setState(() => _status = '失败: $error');
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _initialCleanupPending = false;
        });
      }
    }
  }

  /// 生成当前选中设备的二维码图片。
  Future<void> _generate() async {
    if (_busy && !_initialCleanupPending) return;
    if (_initialCleanupPending) {
      if (_generationQueued) return;
      _generationQueued = true;
      await _initialCleanup;
      _generationQueued = false;
      if (!mounted || _busy) return;
    }
    final devices = _selectedDevices;
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
      final files = await (await _getService()).generate(devices);
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
    }
  }

  /// 压缩最近生成的图片并提交给电脑端文件服务。
  Future<void> _export() async {
    if (_busy) return;
    final files = _generatedFiles;
    if (files == null) {
      setState(() => _status = '请先生成二维码');
      return;
    }
    final pageBuilder = widget.exportPageBuilder;
    final onExport = widget.onExport;
    if (pageBuilder == null && onExport == null) {
      setState(() => _status = '失败: 电脑导出服务未配置');
      return;
    }

    setState(() {
      _busy = true;
      _status = '压缩中';
    });
    try {
      final archive = await (await _getService()).zip(files);
      if (!mounted) return;
      if (pageBuilder != null) {
        setState(() => _status = '正在打开导出页面');
        await Navigator.push<void>(
          context,
          MaterialPageRoute(
            builder: (_) => pageBuilder(archive, '二维码合计.zip'),
          ),
        );
        if (mounted) setState(() => _status = '已返回二维码列表');
        return;
      }
      setState(() => _status = '导出中');
      await onExport!(archive, '二维码合计.zip');
      if (!mounted) return;
      setState(() => _status = '导出已完成');
    } catch (error) {
      if (!mounted) return;
      setState(() => _status = '失败: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 根据设备记录找到最近一次生成的图片文件。
  File? _fileForDevice(QrDevice device) {
    final files = _generatedFiles;
    final devices = _generatedDevices;
    if (files == null || devices == null) return null;
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
          padding: const EdgeInsets.all(12),
          child: InteractiveViewer(
            minScale: .8,
            maxScale: 4,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.file(file, fit: BoxFit.contain),
                const SizedBox(height: 8),
                Text(
                  '${device.deviceNumber}  ·  ${device.deviceName}',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
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
            Container(
              margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: colors.outlineVariant),
              ),
              child: Row(
                children: [
                  Checkbox(
                    key: const Key('select-all-checkbox'),
                    value: _selectAllValue,
                    tristate: true,
                    onChanged: _busy || _devices.isEmpty
                        ? null
                        : (_) => _changeAll(_selectAllValue != true),
                  ),
                  const Text('全选'),
                  const SizedBox(width: 16),
                  Text('已选择 ${_selectedDevices.length}/${_devices.length}'),
                ],
              ),
            ),
            Expanded(
              child: _devices.isEmpty
                  ? Center(
                      child: Text(
                        _hasRequiredHeaders ? '没有可生成的设备数据' : '表格缺少设备编号或设备名称列',
                      ),
                    )
                  : ListView.builder(
                      itemCount: _devices.length,
                      itemBuilder: (context, index) {
                        final device = _devices[index];
                        final file = _fileForDevice(device);
                        return Card(
                          margin: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 4,
                          ),
                          child: ListTile(
                            leading: Checkbox(
                              key: Key('device-checkbox-$index'),
                              value: _selected[index],
                              onChanged: _busy
                                  ? null
                                  : (value) => _changeSelection(
                                        index,
                                        value ?? false,
                                      ),
                            ),
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
                            onTap: file == null
                                ? null
                                : () => _preview(device, file),
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
                    onPressed:
                        _busy && !_initialCleanupPending ? null : _generate,
                    icon: const Icon(Icons.qr_code),
                    label: const Text('生成'),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton.icon(
                    onPressed:
                        _busy || _generatedFiles == null ? null : _export,
                    icon: const Icon(Icons.archive),
                    label: const Text('导出'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
