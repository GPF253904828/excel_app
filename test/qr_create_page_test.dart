import 'dart:io';
import 'dart:typed_data';

import 'package:excel_app/qr_code_service.dart';
import 'package:excel_app/qr_create_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeQrCodeService extends QrCodeService {
  _FakeQrCodeService() : super(Directory.systemTemp);

  @override
  Future<List<File>> generate(List<QrDevice> devices) async => [
        for (final device in devices) File(device.deviceNumber),
      ];

  @override
  Future<Uint8List> zip(List<File> files) async =>
      Uint8List.fromList([0x50, 0x4B]);
}

void main() {
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('qr_page_test_');
  });

  tearDown(() async {
    if (directory.existsSync()) await directory.delete(recursive: true);
  });

  Widget buildPage({
    Future<void> Function(Uint8List bytes, String filename)? onExport,
  }) {
    return MaterialApp(
      home: QrCreatePage(
        headers: const ['设备编号', '设备名称'],
        rows: const [
          ['P001', '设备A'],
          ['P002', '设备B'],
        ],
        service: _FakeQrCodeService(),
        onExport: onExport,
      ),
    );
  }

  testWidgets('starts with all devices selected and supports select all',
      (tester) async {
    await tester.pumpWidget(buildPage());

    expect(
      tester
          .widget<Checkbox>(find.byKey(const Key('select-all-checkbox')))
          .value,
      isTrue,
    );
    expect(
      tester.widget<Checkbox>(find.byKey(const Key('device-checkbox-0'))).value,
      isTrue,
    );

    await tester.tap(find.byKey(const Key('device-checkbox-0')));
    await tester.pump();
    expect(
      tester
          .widget<Checkbox>(find.byKey(const Key('select-all-checkbox')))
          .value,
      isNull,
    );

    await tester.tap(find.byKey(const Key('select-all-checkbox')));
    await tester.pump();
    expect(
      tester.widget<Checkbox>(find.byKey(const Key('device-checkbox-0'))).value,
      isTrue,
    );
    expect(
      tester.widget<Checkbox>(find.byKey(const Key('device-checkbox-1'))).value,
      isTrue,
    );
  });

  testWidgets('shows validation when generating with no selected rows',
      (tester) async {
    await tester.pumpWidget(buildPage());

    await tester.tap(find.byKey(const Key('select-all-checkbox')));
    await tester.pump();
    await tester.tap(find.text('生成'));
    await tester.pump();

    expect(find.text('请至少选择一条设备数据'), findsOneWidget);
  });

  testWidgets('shows generation and export completion states', (tester) async {
    Uint8List? exportedBytes;
    String? exportedName;
    await tester.pumpWidget(buildPage(onExport: (bytes, filename) async {
      exportedBytes = bytes;
      exportedName = filename;
    }));

    await tester.tap(find.text('生成'));
    await tester.pumpAndSettle();
    expect(find.text('生成已完成'), findsOneWidget);

    await tester.tap(find.text('导出'));
    await tester.pumpAndSettle();
    expect(find.text('导出已完成'), findsOneWidget);
    expect(exportedName, '二维码合计.zip');
    expect(exportedBytes, isNotNull);
  });
}
