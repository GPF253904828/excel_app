import 'dart:io';
import 'dart:typed_data';

import 'package:excel_app/device_edit_page.dart';
import 'package:excel_app/network_tools/xls_reader.dart';
import 'package:excel_app/qr_create_page.dart';
import 'package:excel_app/scanner_page.dart';
import 'package:excel_app/utils/toast_util.dart';
import 'package:flutter/material.dart';

const double _minColumnWidth = 72;
const double _maxColumnWidth = 220;

/// 根据表头和数据内容计算单列宽度，避免短列产生过多留白。
double spreadsheetColumnWidth(String header, Iterable<String> values) {
  final candidates = <String>[header, ...values];
  final painter = TextPainter(
    textDirection: TextDirection.ltr,
    maxLines: 1,
  );
  var width = 0.0;
  for (final value in candidates) {
    painter.text = TextSpan(
      text: value,
      style: const TextStyle(fontSize: 14),
    );
    painter.layout();
    width = width < painter.width ? painter.width : width;
  }
  return (width + 24).clamp(_minColumnWidth, _maxColumnWidth).toDouble();
}

/// 按设备编号精确查找行，匹配时忽略编号首尾空白。
int findDeviceRowIndex(
  List<String> headers,
  List<List<String>> rows,
  String deviceNumber,
) {
  final numberIndex = headers.indexOf('设备编号');
  if (numberIndex < 0) return -1;

  final target = deviceNumber.trim();
  for (var rowIndex = 0; rowIndex < rows.length; rowIndex++) {
    final row = rows[rowIndex];
    if (numberIndex < row.length && row[numberIndex].trim() == target) {
      return rowIndex;
    }
  }
  return -1;
}

/// 提供 Excel 表格的新增、编辑、删除和保存操作。
class SpreadsheetPage extends StatefulWidget {
  final File file;
  final XlsTable table;
  final Future<void> Function(XlsTable table) onSave;
  final Future<void> Function(Uint8List bytes, String filename)?
      onExportQrCodes;

  const SpreadsheetPage({
    super.key,
    required this.file,
    required this.table,
    required this.onSave,
    this.onExportQrCodes,
  });

  @override
  State<SpreadsheetPage> createState() => _SpreadsheetPageState();
}

class _SpreadsheetPageState extends State<SpreadsheetPage> {
  late final List<String> _headers;
  late final List<List<String>> _rows;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _headers = List<String>.from(widget.table.headers);
    _rows = widget.table.rows.map(List<String>.from).toList();
  }

  /// 打开新增行编辑页，只有保存成功后才追加到当前列表。
  Future<void> _addRow() => _openEditor();

  /// 打开相机扫描设备编号，并进入匹配行的编辑页。
  Future<void> _scanRow() async {
    if (!_headers.contains('设备编号')) {
      ToastUtil.showCenter('表格中没有设备编号列');
      return;
    }

    final deviceNumber = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const ScannerPage()),
    );
    if (deviceNumber == null || !mounted) return;

    final rowIndex = findDeviceRowIndex(_headers, _rows, deviceNumber);
    if (rowIndex < 0) {
      ToastUtil.showCenter('未找到设备编号：${deviceNumber.trim()}');
      return;
    }
    await _openEditor(rowIndex: rowIndex);
  }

  /// 打开新增或已有行编辑页，并在外部保存成功后更新列表。
  Future<void> _openEditor({int? rowIndex}) async {
    final initialRow = rowIndex == null
        ? List<String>.filled(_headers.length, '')
        : _rowForEditor(_rows[rowIndex]);

    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => DeviceEditPage(
          headers: List<String>.from(_headers),
          initialRow: initialRow,
          isNew: rowIndex == null,
          onSave: (row) => _saveRow(rowIndex, row),
        ),
      ),
    );
  }

  /// 将不完整的数据行补齐为与表头等长，避免编辑页索引错位。
  List<String> _rowForEditor(List<String> row) {
    return List<String>.generate(
      _headers.length,
      (index) => index < row.length ? row[index] : '',
    );
  }

  /// 外部保存成功后替换或追加一行，失败时保持原列表不变。
  Future<void> _saveRow(int? rowIndex, List<String> row) async {
    final normalizedRow = _rowForEditor(row);
    final candidateRows = _rows.map(List<String>.from).toList();
    if (rowIndex == null) {
      candidateRows.add(normalizedRow);
    } else {
      candidateRows[rowIndex] = normalizedRow;
    }

    await widget.onSave(XlsTable(
      headers: List<String>.from(_headers),
      rows: candidateRows,
    ));
    if (!mounted) return;

    setState(() {
      _rows
        ..clear()
        ..addAll(candidateRows);
    });
    ToastUtil.showCenter('已保存，等待电脑接收');
  }

  /// 长按数据行后确认删除。
  Future<void> _deleteRow(int rowIndex) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('确认删除'),
          content: const Text('确定删除这条数据吗？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('取消'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('删除'),
            ),
          ],
        );
      },
    );

    if (shouldDelete != true || !mounted) return;
    setState(() {
      _rows.removeAt(rowIndex);
    });
  }

  /// 二次确认后把当前编辑结果发送到电脑页面。
  Future<void> _save() async {
    if (_saving) return;

    final shouldSave = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('确认保存'),
          content: const Text('保存后将发送到电脑，是否继续？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('取消'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('保存'),
            ),
          ],
        );
      },
    );

    if (shouldSave != true || !mounted) return;
    setState(() => _saving = true);
    try {
      await widget.onSave(XlsTable(
        headers: List<String>.from(_headers),
        rows: _rows.map(List<String>.from).toList(),
      ));
      if (!mounted) return;
      ToastUtil.showCenter('已保存，等待电脑接收');
    } catch (error) {
      if (!mounted) return;
      ToastUtil.showCenter('保存失败: $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// 打开二维码页面并传入当前编辑中的表格数据。
  Future<void> _openQrCreatePage() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => QrCreatePage(
          headers: List<String>.from(_headers),
          rows: _rows.map(List<String>.from).toList(),
          onExport: widget.onExportQrCodes,
        ),
      ),
    );
  }

  /// 构建表格工具栏和双向滚动区域。
  @override
  Widget build(BuildContext context) {
    final widths = List<double>.generate(_headers.length, (index) {
      final values = _rows.map((row) => row[index]);
      return spreadsheetColumnWidth(_headers[index], values);
    });

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.file.uri.pathSegments.last),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Row(
              children: [
                IconButton(
                  tooltip: '新增一行',
                  onPressed: _addRow,
                  icon: const Icon(Icons.add),
                ),
                IconButton(
                  tooltip: '扫描二维码',
                  onPressed: _scanRow,
                  icon: const Icon(Icons.qr_code_scanner),
                ),
                IconButton(
                  tooltip: '生成二维码',
                  onPressed: _openQrCreatePage,
                  icon: const Icon(Icons.qr_code),
                ),
                const Spacer(),
                Text('共 ${_rows.length} 条数据'),
                const Spacer(),
                IconButton(
                  tooltip: '保存',
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save),
                ),
              ],
            ),
            Expanded(
              child: SingleChildScrollView(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    horizontalMargin: 8,
                    columnSpacing: 8,
                    headingRowColor:
                        MaterialStateProperty.all(Colors.blue.shade50),
                    columns:
                        List<DataColumn>.generate(_headers.length, (index) {
                      return DataColumn(
                        label: SizedBox(
                          width: widths[index],
                          child: Text(
                            _headers[index],
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      );
                    }),
                    rows: List<DataRow>.generate(_rows.length, (rowIndex) {
                      return DataRow(
                        onLongPress: () => _deleteRow(rowIndex),
                        cells: List<DataCell>.generate(_rows[rowIndex].length,
                            (columnIndex) {
                          return DataCell(
                            SizedBox(
                              width: widths[columnIndex],
                              child: Text(
                                _rows[rowIndex][columnIndex],
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            onTap: () => _openEditor(rowIndex: rowIndex),
                            onLongPress: () => _deleteRow(rowIndex),
                          );
                        }),
                      );
                    }),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
