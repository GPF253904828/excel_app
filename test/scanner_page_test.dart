import 'package:excel_app/scanner_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

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
}
