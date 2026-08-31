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

/// 在线表格新增或编辑一行后返回最新的完整表格。
typedef SpreadsheetRowSaveCallback = Future<XlsTable> Function(
  int? rowIndex,
  List<String> row,
);

/// 在线表格删除一行后返回最新的完整表格。
typedef SpreadsheetRowDeleteCallback = Future<XlsTable> Function(
  int rowIndex,
  List<String> row,
);

bool _isNormalStatus(String status) => status == '正常使用' || status == '正常';
bool _isRepairStatus(String status) => status == '维修中' || status == '维修';

/// 根据状态和计量有效期返回数据行的提示色。
Color? spreadsheetRowColor(
  BuildContext context,
  List<String> headers,
  List<String> row,
) {
  final statusIndex = headers.indexOf('状态');
  final status = statusIndex >= 0 && statusIndex < row.length
      ? row[statusIndex].trim()
      : '';
  final colors = Theme.of(context).colorScheme;
  if (status == '报废') return colors.errorContainer.withOpacity(.62);
  if (_isRepairStatus(status)) return const Color(0xFFFFF1D6);

  final expiryIndex = headers.indexWhere(
    (header) => header.contains('计量有效期至') || header.contains('有效期'),
  );
  if (expiryIndex < 0 || expiryIndex >= row.length) {
    return _isNormalStatus(status) ? const Color(0xFFE7F5EC) : null;
  }
  final expiry = _parseSpreadsheetDate(row[expiryIndex]);
  if (expiry == null) {
    return _isNormalStatus(status) ? const Color(0xFFE7F5EC) : null;
  }
  final today = DateTime.now();
  final dateOnly = DateTime(today.year, today.month, today.day);
  if (expiry.isBefore(dateOnly)) return colors.errorContainer.withOpacity(.42);
  if (!expiry.isAfter(dateOnly.add(const Duration(days: 30)))) {
    return const Color(0xFFFFF6D9);
  }
  if (_isNormalStatus(status)) return const Color(0xFFE7F5EC);
  return null;
}

/// 兼容 XLS 常见的日期文本格式，统一成不含时间的本地日期。
DateTime? _parseSpreadsheetDate(String value) {
  final normalized = value.trim().replaceAll('/', '-');
  final match = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})').firstMatch(normalized);
  if (match == null) return null;
  return DateTime.tryParse(
    '${match.group(1)}-${match.group(2)!.padLeft(2, '0')}-${match.group(3)!.padLeft(2, '0')}',
  );
}

/// 返回表格中计量有效期字段的索引。
int _expiryIndex(List<String> headers) => headers.indexWhere(
      (header) => header.contains('计量有效期至') || header.contains('有效期'),
    );

/// 判断有效期是否已经进入 30 天预警区间。
bool spreadsheetHasExpiryWarning(List<String> headers, List<String> row) {
  final index = _expiryIndex(headers);
  if (index < 0 || index >= row.length) return false;
  final expiry = _parseSpreadsheetDate(row[index]);
  if (expiry == null) return false;
  final today = DateTime.now();
  final dateOnly = DateTime(today.year, today.month, today.day);
  return !expiry.isAfter(dateOnly.add(const Duration(days: 30)));
}

/// 返回点击有效期警告时展示的完整提示文本。
String? spreadsheetExpiryNotice(List<String> headers, List<String> row) {
  final index = _expiryIndex(headers);
  if (index < 0 ||
      index >= row.length ||
      !spreadsheetHasExpiryWarning(headers, row)) {
    return null;
  }
  return '计量有效期至 ${row[index].trim()}';
}

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
  final Future<void> Function(XlsTable table)? onSave;
  final SpreadsheetRowSaveCallback? onSaveRow;
  final SpreadsheetRowDeleteCallback? onDeleteRow;
  final String? title;
  final List<Widget> appBarActions;
  final Future<void> Function(Uint8List bytes, String filename)?
      onExportQrCodes;

  const SpreadsheetPage({
    super.key,
    required this.file,
    required this.table,
    this.onSave,
    this.onSaveRow,
    this.onDeleteRow,
    this.title,
    this.appBarActions = const <Widget>[],
    this.onExportQrCodes,
  });

  @override
  State<SpreadsheetPage> createState() => _SpreadsheetPageState();
}

class _SpreadsheetPageState extends State<SpreadsheetPage> {
  late List<String> _headers;
  late List<List<String>> _rows;
  late final ScrollController _horizontalController;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _applyTable(widget.table);
    _horizontalController = ScrollController();
  }

  /// 将表格数据复制为页面拥有的可编辑列表。
  void _applyTable(XlsTable table) {
    _headers = List<String>.from(table.headers);
    _rows = table.rows
        .map((row) => List<String>.generate(
              _headers.length,
              (index) => index < row.length ? row[index] : '',
            ))
        .toList();
  }

  /// 在父级传入新表格时替换本地可编辑副本。
  @override
  void didUpdateWidget(covariant SpreadsheetPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.table, widget.table)) {
      setState(() => _applyTable(widget.table));
    }
  }

  @override
  void dispose() {
    _horizontalController.dispose();
    super.dispose();
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

  /// 打开新增或已有行编辑页，编辑页保存后只更新当前列表。
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

  /// 将编辑结果替换或追加到当前列表，等待列表页保存按钮上传。
  Future<void> _saveRow(int? rowIndex, List<String> row) async {
    final normalizedRow = _rowForEditor(row);
    final onSaveRow = widget.onSaveRow;
    if (onSaveRow != null) {
      final synchronizedTable = await onSaveRow(rowIndex, normalizedRow);
      if (!mounted) return;
      setState(() => _applyTable(synchronizedTable));
      ToastUtil.showCenter('已同步线上列表');
      return;
    }

    final candidateRows = _rows.map(List<String>.from).toList();
    if (rowIndex == null) {
      candidateRows.add(normalizedRow);
    } else {
      candidateRows[rowIndex] = normalizedRow;
    }

    setState(() {
      _rows
        ..clear()
        ..addAll(candidateRows);
    });
    ToastUtil.showCenter('已更新列表，点击列表页保存上传到电脑');
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
    final onDeleteRow = widget.onDeleteRow;
    if (onDeleteRow != null) {
      try {
        final synchronizedTable =
            await onDeleteRow(rowIndex, List<String>.from(_rows[rowIndex]));
        if (!mounted) return;
        setState(() => _applyTable(synchronizedTable));
        ToastUtil.showCenter('已同步线上列表');
      } catch (error) {
        if (mounted) ToastUtil.showCenter('删除失败: $error');
      }
      return;
    }
    setState(() {
      _rows.removeAt(rowIndex);
    });
  }

  /// 二次确认后把当前编辑结果发送到电脑页面。
  Future<void> _save() async {
    final onSave = widget.onSave;
    if (_saving || onSave == null) return;

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
      await onSave(XlsTable(
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

  /// 构建固定表头和可独立滚动的数据区域。
  @override
  Widget build(BuildContext context) {
    final widths = List<double>.generate(_headers.length, (index) {
      final values = _rows.map((row) => row[index]);
      return spreadsheetColumnWidth(_headers[index], values);
    });

    final tableWidth = widths.fold<double>(0, (sum, width) => sum + width);
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 72,
        title: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    widget.title ?? widget.file.uri.pathSegments.last,
                    maxLines: 2,
                    softWrap: true,
                  ),
                  Text(
                    '共 ${_rows.length} 条数据',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          ...widget.appBarActions,
          IconButton(
            tooltip: '新增一行',
            onPressed: _addRow,
            color: colors.onSurfaceVariant,
            icon: const Icon(Icons.add),
          ),
          IconButton(
            tooltip: '生成二维码',
            onPressed: _openQrCreatePage,
            color: colors.onSurfaceVariant,
            icon: const Icon(Icons.qr_code_2),
          ),
          const SizedBox(width: 8),
        ],
      ),
      floatingActionButton: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            FloatingActionButton.small(
              heroTag: 'scan-row',
              tooltip: '扫描二维码',
              onPressed: _scanRow,
              child: const Icon(Icons.document_scanner_outlined),
            ),
            const SizedBox(height: 12),
            if (widget.onSave != null && widget.onSaveRow == null)
              FloatingActionButton.small(
                heroTag: 'save-table',
                tooltip: '保存',
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_outlined),
              ),
          ],
        ),
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              controller: _horizontalController,
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(0, 8, 0, 20),
              child: SizedBox(
                width: tableWidth < constraints.maxWidth
                    ? constraints.maxWidth
                    : tableWidth,
                height: constraints.maxHeight - 28,
                child: Column(
                  children: [
                    _buildHeader(_filledWidths(widths, constraints.maxWidth)),
                    const SizedBox(height: 1),
                    Expanded(
                      child: _rows.isEmpty
                          ? Center(
                              child: Text(
                                '暂无数据',
                                style:
                                    TextStyle(color: colors.onSurfaceVariant),
                              ),
                            )
                          : ListView.builder(
                              itemCount: _rows.length,
                              itemBuilder: (context, rowIndex) => _buildRow(
                                rowIndex,
                                _filledWidths(widths, constraints.maxWidth),
                              ),
                            ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  /// 将最后一列补足到屏幕宽度，避免表格右侧留下空白。
  List<double> _filledWidths(List<double> widths, double viewportWidth) {
    final result = List<double>.from(widths);
    final tableWidth = widths.fold<double>(0, (sum, width) => sum + width);
    if (result.isNotEmpty && viewportWidth > tableWidth) {
      result[result.length - 1] += viewportWidth - tableWidth;
    }
    return result;
  }

  /// 构建不参与垂直滚动的表头行。
  Widget _buildHeader(List<double> widths) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: colors.primaryContainer.withOpacity(.72),
      ),
      child: Table(
        columnWidths: _columnWidths(widths),
        children: [
          TableRow(
            children: _headers
                .map(
                  (header) => _tableCell(
                    header,
                    bold: true,
                    color: colors.onPrimaryContainer,
                    height: 52,
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }

  /// 构建带有状态和有效期提示色的数据行。
  Widget _buildRow(int rowIndex, List<double> widths) {
    final row = _rows[rowIndex];
    final textColor = _rowTextColor(row);
    return Padding(
      padding: const EdgeInsets.only(top: 1),
      child: Material(
        color: Colors.white,
        child: InkWell(
          onTap: () => _openEditor(rowIndex: rowIndex),
          onLongPress: () => _deleteRow(rowIndex),
          child: Table(
            columnWidths: _columnWidths(widths),
            children: [
              TableRow(
                children: List<Widget>.generate(_headers.length, (columnIndex) {
                  final value = row[columnIndex];
                  return _tableCell(value, color: textColor);
                }),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 根据状态为整行文字选择提示色，背景保持统一白色。
  Color? _rowTextColor(List<String> row) {
    final statusIndex = _headers.indexOf('状态');
    final status = statusIndex >= 0 && statusIndex < row.length
        ? row[statusIndex].trim()
        : '';
    if (status == '报废') return const Color(0xFFB42318);
    if (_isRepairStatus(status)) return const Color(0xFFB77900);
    return null;
  }

  /// 创建固定宽度的表格单元格，保证表头和数据列始终对齐。
  Widget _tableCell(
    String value, {
    bool bold = false,
    Color? color,
    double height = 56,
  }) {
    return Container(
      height: height,
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Text(
        value,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: color,
          fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
          fontSize: 14,
        ),
      ),
    );
  }

  /// 将列宽转换成 Table 所需的固定列宽配置。
  Map<int, TableColumnWidth> _columnWidths(List<double> widths) => {
        for (var index = 0; index < widths.length; index++)
          index: FixedColumnWidth(widths[index]),
      };
}
