import 'dart:convert';

import 'package:excel_app/network_tools/csv_exporter.dart';
import 'package:excel_app/network_tools/xls_reader.dart';
import 'package:flutter_test/flutter_test.dart';

/// 验证导出内容是有效 CSV，并正确转义 CSV 特殊字符。
void main() {
  test('exports a CSV table', () {
    final bytes = CsvExporter().export(
      XlsTable(
        headers: ['名称', '备注'],
        rows: [
          ['<测试>', 'A,B']
        ],
      ),
    );
    final csv = utf8.decode(bytes.sublist(3));

    expect(csv, contains('名称,备注'));
    expect(csv, contains('<测试>'));
    expect(csv, contains('"A,B"'));
  });
}
