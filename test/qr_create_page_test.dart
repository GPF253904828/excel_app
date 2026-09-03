import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:excel_app/qr/qr_code_service.dart';
import 'package:excel_app/qr/qr_create_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeQrCodeService extends QrCodeService {
  bool clearCalled = false;

  _FakeQrCodeService() : super(Directory.systemTemp);

  @override
  Future<void> clear() async {
    clearCalled = true;
  }

  @override
  Future<List<File>> generate(List<QrDevice> devices) async => [
        for (final device in devices) File(device.deviceNumber),
      ];

  @override
  Future<Uint8List> zip(List<File> files) async =>
      Uint8List.fromList([0x50, 0x4B]);
}

class _DelayedClearQrCodeService extends QrCodeService {
  final clearCompleter = Completer<void>();
  bool generateCalled = false;

  _DelayedClearQrCodeService() : super(Directory.systemTemp);

  @override
  Future<void> clear() => clearCompleter.future;

  @override
  Future<List<File>> generate(List<QrDevice> devices) async {
    generateCalled = true;
    return [for (final device in devices) File(device.deviceNumber)];
  }
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
    QrCodeService? service,
    Future<void> Function(Uint8List bytes, String filename)? onExport,
  }) {
    return MaterialApp(
      home: QrCreatePage(
        headers: const ['设备编号', '设备名称'],
        rows: const [
          ['P001', '设备A'],
          ['P002', '设备B'],
        ],
        service: service ?? _FakeQrCodeService(),
        onExport: onExport,
      ),
    );
  }

  testWidgets('clears existing QR files when the page opens', (tester) async {
    final service = _FakeQrCodeService();

    await tester.pumpWidget(buildPage(service: service));
    await tester.pumpAndSettle();

    expect(service.clearCalled, isTrue);
  });

  testWidgets('removes existing PNG files from the real output directory',
      (tester) async {
    final staleFile = File('${directory.path}/stale.png')
      ..writeAsStringSync('stale');

    await tester.pumpWidget(buildPage(service: QrCodeService(directory)));
    await tester.runAsync(() async {
      for (var attempt = 0; staleFile.existsSync() && attempt < 20; attempt++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    await tester.pump();

    expect(staleFile.existsSync(), isFalse);
  });

  testWidgets('queues generation until initial cleanup completes',
      (tester) async {
    final service = _DelayedClearQrCodeService();

    await tester.pumpWidget(buildPage(service: service));
    await tester.tap(find.text('生成'));
    await tester.pump();
    expect(service.generateCalled, isFalse);

    service.clearCompleter.complete();
    await tester.pumpAndSettle();
    expect(service.generateCalled, isTrue);
  });

  testWidgets('starts with all devices selected and supports select all',
      (tester) async {
    await tester.pumpWidget(buildPage());
    await tester.pumpAndSettle();

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
    await tester.pumpAndSettle();

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
    await tester.pumpAndSettle();

    await tester.tap(find.text('生成'));
    await tester.pumpAndSettle();
    expect(find.text('生成已完成'), findsOneWidget);

    await tester.tap(find.text('导出'));
    await tester.pumpAndSettle();
    expect(find.text('导出已完成'), findsOneWidget);
    expect(exportedName, '二维码合计.zip');
    expect(exportedBytes, isNotNull);
  });

  testWidgets('opens a secondary export page after generating QR files',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: QrCreatePage(
          headers: const ['设备编号', '设备名称'],
          rows: const [
            ['P001', '设备A']
          ],
          service: _FakeQrCodeService(),
          exportPageBuilder: (_, filename) => Scaffold(
            body: Center(child: Text(filename)),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('生成'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('导出'));
    await tester.pumpAndSettle();

    expect(find.text('二维码合计.zip'), findsOneWidget);
  });
}
