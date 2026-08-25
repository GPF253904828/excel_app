import 'dart:async';

import 'package:excel_app/scanner_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class _PopObserver extends NavigatorObserver {
  int popCount = 0;

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    popCount++;
    super.didPop(route, previousRoute);
  }
}

void main() {
  test('firstScanValue returns the first trimmed non-empty raw value', () {
    final capture = BarcodeCapture(
      barcodes: [
        const Barcode(rawValue: null),
        const Barcode(rawValue: '  '),
        const Barcode(rawValue: '  DEVICE-001  '),
        const Barcode(rawValue: 'DEVICE-002'),
      ],
    );

    expect(firstScanValue(capture), 'DEVICE-001');
  });

  test('firstScanValue returns null when all raw values are empty', () {
    final capture = BarcodeCapture(
      barcodes: [
        const Barcode(rawValue: null),
        const Barcode(rawValue: ''),
        const Barcode(rawValue: ' \n\t'),
      ],
    );

    expect(firstScanValue(capture), isNull);
  });

  testWidgets('scanner page contains the scanner and cancel action',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: ScannerPage(),
      ),
    );

    expect(find.byType(MobileScanner), findsOneWidget);
    expect(find.text('取消'), findsOneWidget);
  });

  testWidgets('returns one scan result after stopping and ignores duplicates',
      (tester) async {
    String? result;
    final popObserver = _PopObserver();
    final stopCompleted = Completer<Object?>();
    const methodChannel = MethodChannel(
      'dev.steenbakker.mobile_scanner/scanner/method',
    );
    TestDefaultBinaryMessengerBinding.instance!.defaultBinaryMessenger
        .setMockMethodCallHandler(methodChannel, (call) async {
      if (call.method == 'stop') return stopCompleted.future;
      if (call.method == 'state') return 0;
      if (call.method == 'request') return false;
      return true;
    });

    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [popObserver],
        home: Builder(
          builder: (context) {
            return ElevatedButton(
              onPressed: () async {
                result = await Navigator.push<String>(
                  context,
                  MaterialPageRoute(builder: (_) => const ScannerPage()),
                );
              },
              child: const Text('打开'),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();

    final scanner = tester.widget<MobileScanner>(find.byType(MobileScanner));
    final capture = BarcodeCapture(
      barcodes: [const Barcode(rawValue: 'DEVICE-003')],
    );
    scanner.onDetect(capture);
    scanner.onDetect(capture);

    expect(popObserver.popCount, 0);
    expect(result, isNull);
    stopCompleted.complete();
    await tester.pumpAndSettle();

    expect(result, 'DEVICE-003');
    expect(popObserver.popCount, 1);
    expect(find.byType(ScannerPage), findsNothing);

    TestDefaultBinaryMessengerBinding.instance!.defaultBinaryMessenger
        .setMockMethodCallHandler(methodChannel, null);
  });
}
