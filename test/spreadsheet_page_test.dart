import 'package:excel_app/spreadsheet_page.dart';
import 'dart:io';

import 'package:excel_app/network_tools/xls_reader.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 验证列宽会随内容变化，并且不会无限扩大。
void main() {
  test('column width follows content and stays within bounds', () {
    final shortWidth = spreadsheetColumnWidth('状态', ['正常使用']);
    final longWidth = spreadsheetColumnWidth(
      '设备名称',
      ['HERAEUS台式高速离心机'],
    );

    expect(longWidth, greaterThan(shortWidth));
    expect(shortWidth, greaterThanOrEqualTo(72));
    expect(longWidth, lessThanOrEqualTo(220));
  });

  testWidgets('supports adding and deleting rows with confirmation',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SpreadsheetPage(
          file: File('device_list.xls'),
          table: XlsTable(headers: [
            '设备编号',
            '设备名称',
            '设备型号'
          ], rows: [
            ['P001', '设备A', '型号A']
          ]),
          onSave: (_) async {},
        ),
      ),
    );

    await tester.tap(find.byTooltip('新增一行'));
    await tester.pump();
    expect(find.text('共 2 条数据'), findsOneWidget);

    await tester.longPress(find.text('设备A'));
    await tester.pump();
    expect(find.text('确认删除'), findsOneWidget);

    await tester.tap(find.text('删除'));
    await tester.pump();
    expect(find.text('设备A'), findsNothing);
    expect(find.text('共 1 条数据'), findsOneWidget);
  });

  testWidgets('edits a cell and confirms saving the changed table',
      (tester) async {
    XlsTable? savedTable;
    await tester.pumpWidget(
      MaterialApp(
        home: SpreadsheetPage(
          file: File('device_list.xls'),
          table: XlsTable(headers: [
            '设备编号',
            '设备名称',
            '设备型号'
          ], rows: [
            ['P001', '设备A', '型号A']
          ]),
          onSave: (table) async => savedTable = table,
        ),
      ),
    );

    await tester.tap(find.text('型号A'));
    await tester.pump();
    expect(find.text('修改设备编号 P001、设备名称 设备A的 设备型号信息'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '设备B');
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    expect(find.text('设备B'), findsOneWidget);

    await tester.tap(find.byTooltip('保存'));
    await tester.pump();
    expect(find.text('确认保存'), findsOneWidget);
    await tester.tap(find.text('保存'));
    await tester.pump();

    expect(savedTable?.rows.single[2], '设备B');
  });
}
