import 'dart:io';

import 'package:excel_app/device_edit_page.dart';
import 'package:excel_app/network_tools/xls_reader.dart';
import 'package:excel_app/qr_create_page.dart';
import 'package:excel_app/scanner_page.dart';
import 'package:excel_app/spreadsheet_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// 验证表格页面的列宽计算和行编辑流程。
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

  test('finds a device row by trimmed exact device number', () {
    expect(
      findDeviceRowIndex(
        ['设备编号', '设备名称'],
        [
          [' P001 ', '设备A'],
          ['P002', '设备B'],
        ],
        ' P001 ',
      ),
      0,
    );
    expect(
      findDeviceRowIndex(
        ['设备编号', '设备名称'],
        [
          ['P001', '设备A']
        ],
        'P003',
      ),
      -1,
    );
  });

  testWidgets('opens the editor without adding until the new row is saved',
      (tester) async {
    XlsTable? savedTable;
    await tester.pumpWidget(_spreadsheetApp(
      table: XlsTable(
        headers: const ['设备编号', '设备名称', '设备型号'],
        rows: const [
          ['P001', '设备A', '型号A']
        ],
      ),
      onSave: (table) async => savedTable = table,
    ));

    await tester.tap(find.byTooltip('新增一行'));
    await tester.pumpAndSettle();
    expect(find.byType(DeviceEditPage), findsOneWidget);
    expect(find.text('共 1 条数据', skipOffstage: false), findsOneWidget);

    await tester.enterText(find.byKey(const Key('field-设备编号')), 'P002');
    await tester.enterText(find.byKey(const Key('field-设备名称')), '设备B');
    await tester.enterText(find.byKey(const Key('field-设备型号')), '型号B');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(find.byType(DeviceEditPage), findsNothing);
    expect(find.text('共 2 条数据'), findsOneWidget);
    expect(savedTable, isNull);

    await tester.tap(find.byTooltip('保存'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(savedTable?.rows.last, ['P002', '设备B', '型号B']);

    await tester.longPress(find.text('设备A'));
    await tester.pump();
    expect(find.text('确认删除'), findsOneWidget);
    await tester.tap(find.text('删除'));
    await tester.pump();
    expect(find.text('设备A'), findsNothing);
    expect(find.text('共 1 条数据'), findsOneWidget);
  });

  testWidgets('edits a complete row and uploads only from the list page',
      (tester) async {
    XlsTable? savedTable;
    await tester.pumpWidget(_spreadsheetApp(
      table: XlsTable(
        headers: const ['设备编号', '设备名称', '设备型号'],
        rows: const [
          ['P001', '设备A', '型号A']
        ],
      ),
      onSave: (table) async => savedTable = table,
    ));

    await tester.tap(find.text('型号A'));
    await tester.pumpAndSettle();
    expect(find.byType(DeviceEditPage), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byKey(const Key('field-设备编号'))).enabled,
      isFalse,
    );
    await tester.enterText(find.byKey(const Key('field-设备型号')), '型号B');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(savedTable, isNull);
    expect(find.text('型号B'), findsOneWidget);

    await tester.tap(find.byTooltip('保存'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(savedTable?.rows.single, ['P001', '设备A', '型号B']);
  });

  testWidgets('keeps the list unchanged when list upload fails',
      (tester) async {
    await tester.pumpWidget(_spreadsheetApp(
      table: XlsTable(
        headers: const ['设备编号', '设备名称'],
        rows: const [
          ['P001', '设备A']
        ],
      ),
      onSave: (_) async => throw '网络错误',
    ));

    await tester.tap(find.text('设备A'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('field-设备名称')), '设备B');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(find.byType(DeviceEditPage), findsNothing);
    expect(find.text('设备B'), findsOneWidget);
    await tester.tap(find.byTooltip('保存'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(find.text('共 1 条数据'), findsOneWidget);
    expect(find.text('设备B'), findsOneWidget);
  });

  testWidgets('shows a message when a scanned device is not found',
      (tester) async {
    _mockScannerChannel();
    await tester.pumpWidget(_spreadsheetApp(
      table: XlsTable(
        headers: const ['设备编号', '设备名称'],
        rows: const [
          ['P001', '设备A']
        ],
      ),
      onSave: (_) async {},
    ));

    await tester.tap(find.byTooltip('扫描二维码'));
    await tester.pumpAndSettle();
    final scanner = tester.widget<MobileScanner>(find.byType(MobileScanner));
    scanner.onDetect(
      BarcodeCapture(barcodes: [const Barcode(rawValue: 'P999')]),
    );
    await tester.pumpAndSettle();

    expect(find.byType(DeviceEditPage), findsNothing);
    expect(find.text('共 1 条数据'), findsOneWidget);
  });

  testWidgets('opens the matched row after scanning its device number',
      (tester) async {
    _mockScannerChannel();
    await tester.pumpWidget(_spreadsheetApp(
      table: XlsTable(
        headers: const ['设备编号', '设备名称'],
        rows: const [
          ['P001', '设备A']
        ],
      ),
      onSave: (_) async {},
    ));

    await tester.tap(find.byTooltip('扫描二维码'));
    await tester.pumpAndSettle();
    tester.widget<MobileScanner>(find.byType(MobileScanner)).onDetect(
          BarcodeCapture(barcodes: [const Barcode(rawValue: ' P001 ')]),
        );
    await tester.pumpAndSettle();

    expect(find.byType(DeviceEditPage), findsOneWidget);
    expect(find.byKey(const Key('field-设备编号')), findsOneWidget);
    expect(find.text('设备A'), findsOneWidget);
  });

  testWidgets('shows a message when the table has no device number column',
      (tester) async {
    await tester.pumpWidget(_spreadsheetApp(
      table: XlsTable(
        headers: const ['设备名称'],
        rows: const [
          ['设备A']
        ],
      ),
      onSave: (_) async {},
    ));

    await tester.tap(find.byTooltip('扫描二维码'));
    await tester.pumpAndSettle();
    expect(find.byType(ScannerPage), findsNothing);
    expect(find.text('共 1 条数据'), findsOneWidget);
  });

  testWidgets('opens QR creation page with the current table rows',
      (tester) async {
    await tester.pumpWidget(_spreadsheetApp(
      table: XlsTable(
        headers: const ['设备编号', '设备名称'],
        rows: const [
          ['P001', '设备A']
        ],
      ),
      onSave: (_) async {},
    ));

    await tester.tap(find.byTooltip('生成二维码'));
    await tester.pumpAndSettle();

    expect(find.byType(QrCreatePage), findsOneWidget);
    expect(find.text('P001'), findsOneWidget);
    expect(find.text('设备A'), findsOneWidget);
  });

  testWidgets('uses remote row callbacks and replaces rows after editing',
      (tester) async {
    int? savedIndex;
    List<String>? savedRow;
    await tester.pumpWidget(_spreadsheetApp(
      table: XlsTable(
        headers: const ['设备编号', '设备名称'],
        rows: const [
          ['P001', '设备A']
        ],
      ),
      onSaveRow: (rowIndex, row) async {
        savedIndex = rowIndex;
        savedRow = row;
        return XlsTable(
          headers: const ['设备编号', '设备名称'],
          rows: const [
            ['P001', '线上同步后的设备']
          ],
        );
      },
    ));

    expect(find.byTooltip('保存'), findsNothing);
    await tester.tap(find.text('设备A'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('field-设备名称')), '编辑后设备');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(savedIndex, 0);
    expect(savedRow, ['P001', '编辑后设备']);
    expect(find.text('线上同步后的设备'), findsOneWidget);
  });

  testWidgets('uses remote delete callback and replaces rows after deletion',
      (tester) async {
    int? deletedIndex;
    await tester.pumpWidget(_spreadsheetApp(
      table: XlsTable(
        headers: const ['设备编号', '设备名称'],
        rows: const [
          ['P001', '设备A']
        ],
      ),
      onDeleteRow: (rowIndex, row) async {
        deletedIndex = rowIndex;
        return XlsTable(
          headers: const ['设备编号', '设备名称'],
          rows: const [],
        );
      },
    ));

    await tester.longPress(find.text('设备A'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();

    expect(deletedIndex, 0);
    expect(find.text('暂无数据'), findsOneWidget);
  });
}

/// 构造表格页面测试所需的最小应用壳。
Widget _spreadsheetApp({
  required XlsTable table,
  Future<void> Function(XlsTable table)? onSave,
  Future<XlsTable> Function(int? rowIndex, List<String> row)? onSaveRow,
  Future<XlsTable> Function(int rowIndex, List<String> row)? onDeleteRow,
}) {
  return MaterialApp(
    home: SpreadsheetPage(
      file: File('device_list.xls'),
      table: table,
      onSave: onSave,
      onSaveRow: onSaveRow,
      onDeleteRow: onDeleteRow,
    ),
  );
}

/// 为扫码路由提供拒绝权限的最小 platform channel 响应。
void _mockScannerChannel() {
  const methodChannel = MethodChannel(
    'dev.steenbakker.mobile_scanner/scanner/method',
  );
  TestDefaultBinaryMessengerBinding.instance!.defaultBinaryMessenger
      .setMockMethodCallHandler(methodChannel, (call) async {
    if (call.method == 'state') return 0;
    if (call.method == 'request') return false;
    return true;
  });
  addTearDown(() {
    TestDefaultBinaryMessengerBinding.instance!.defaultBinaryMessenger
        .setMockMethodCallHandler(methodChannel, null);
  });
}
