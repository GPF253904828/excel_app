import 'dart:io';

import 'package:excel_app/network_tools/xls_reader.dart';
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

/// 提供 Excel 表格的新增、编辑、删除和保存操作。
class SpreadsheetPage extends StatefulWidget {
  final File file;
  final XlsTable table;
  final Future<void> Function(XlsTable table) onSave;

  const SpreadsheetPage({
    super.key,
    required this.file,
    required this.table,
    required this.onSave,
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

  /// 在表格末尾新增一条空数据。
  void _addRow() {
    setState(() {
      _rows.add(List<String>.filled(_headers.length, ''));
    });
  }

  /// 弹出单元格编辑框并更新对应值。
  Future<void> _editCell(int rowIndex, int columnIndex) async {
    final value = await showDialog<String>(
      context: context,
      builder: (_) => _EditCellDialog(
        title: _editCellTitle(rowIndex, columnIndex),
        initialValue: _rows[rowIndex][columnIndex],
      ),
    );

    if (value == null || !mounted) return;
    setState(() {
      _rows[rowIndex][columnIndex] = value;
    });
  }

  /// 生成包含设备编号和设备名称的编辑提示标题。
  String _editCellTitle(int rowIndex, int columnIndex) {
    final contextValues = <String>[];
    for (final label in ['设备编号', '设备名称']) {
      final index = _headers.indexOf(label);
      if (index < 0) continue;
      final value = _rows[rowIndex][index].trim();
      if (value.isNotEmpty) contextValues.add('$label $value');
    }

    final prefix = contextValues.isEmpty ? '' : '${contextValues.join('、')}的 ';
    return '修改$prefix${_headers[columnIndex]}信息';
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已保存，等待电脑接收')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('保存失败: $error')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
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
                            onTap: () => _editCell(rowIndex, columnIndex),
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

/// 管理单元格编辑输入框的生命周期，避免退出动画期间提前释放 controller。
class _EditCellDialog extends StatefulWidget {
  final String title;
  final String initialValue;

  const _EditCellDialog({
    required this.title,
    required this.initialValue,
  });

  @override
  State<_EditCellDialog> createState() => _EditCellDialogState();
}

class _EditCellDialogState extends State<_EditCellDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
  }

  /// 释放编辑框持有的输入控制器。
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// 构建单元格编辑对话框。
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: const InputDecoration(border: OutlineInputBorder()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, _controller.text),
          child: const Text('确定'),
        ),
      ],
    );
  }
}
