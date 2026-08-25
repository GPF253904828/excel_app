import 'dart:io';

import 'package:excel_app/network_tools/xls_reader.dart';
import 'package:flutter_test/flutter_test.dart';

/// 验证设备清单的表头、数据行和 Excel 日期值可以被读取。
void main() {
  test('reads device list xls as a table', () {
    final bytes = File('device_list.xls').readAsBytesSync();
    final table = XlsReader().read(bytes);

    expect(table.headers.first, '部门');
    expect(table.headers.last, '计量有效期至');
    expect(table.rows.length, 47);
    expect(table.rows.first[3], 'ACCB-N-0008');
    expect(table.rows[1].last, '2027-01-25');
  });
}
