import 'dart:convert';
import 'dart:typed_data';

import 'package:excel_app/network_tools/xls_reader.dart';

/// 将表格数据导出为 Excel 可直接打开的 UTF-8 CSV 文件。
class CsvExporter {
  /// 生成带 UTF-8 BOM 的 CSV 内容，确保中文在 Excel 中正常显示。
  Uint8List export(XlsTable table) {
    final rows = <List<String>>[table.headers, ...table.rows];
    final csv = '${rows.map(_encodeRow).join('\r\n')}\r\n';
    return Uint8List.fromList([0xEF, 0xBB, 0xBF, ...utf8.encode(csv)]);
  }

  /// 转义包含逗号、引号或换行的 CSV 单元格。
  String _escape(String value) {
    if (!value.contains(',') &&
        !value.contains('"') &&
        !value.contains('\r') &&
        !value.contains('\n')) {
      return value;
    }
    return '"${value.replaceAll('"', '""')}"';
  }

  String _encodeRow(List<String> row) => row.map(_escape).join(',');
}
