import 'dart:io';

import 'package:archive/archive.dart';
import 'package:excel_app/qr_code_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('extracts only rows with both device fields', () {
    final devices = extractQrDevices(
      ['设备编号', '设备名称', '型号'],
      [
        [' P001 ', '设备A', 'A'],
        ['P002', '', 'B'],
        ['', '设备C', 'C'],
      ],
    );

    expect(devices, [const QrDevice('P001', '设备A')]);
  });

  test('sanitizes names and adds a suffix for duplicates', () {
    final used = <String>{};

    expect(
      qrFileName(const QrDevice('A/B', '设备:C'), used),
      'A_B设备_C.png',
    );
    expect(
      qrFileName(const QrDevice('A/B', '设备:C'), used),
      'A_B设备_C_2.png',
    );
  });

  test('generates PNG files and a ZIP containing all generated files',
      () async {
    final directory = await Directory.systemTemp.createTemp('qr_service_test_');
    final staleFile = File('${directory.path}/stale.png')
      ..writeAsStringSync('stale');
    final service = QrCodeService(directory);

    try {
      final files = await service.generate(const [
        QrDevice('P001', '设备A'),
        QrDevice('P002', '设备B'),
      ]);
      final archiveBytes = await service.zip(files);
      final archive = ZipDecoder().decodeBytes(archiveBytes);

      expect(staleFile.existsSync(), isFalse);
      expect(files, hasLength(2));
      expect(files.every((file) => file.path.endsWith('.png')), isTrue);
      expect(files.every((file) => file.lengthSync() > 100), isTrue);
      expect(
        archive.files.map((file) => file.name),
        containsAll(['P001设备A.png', 'P002设备B.png']),
      );
    } finally {
      await directory.delete(recursive: true);
    }
  });
}
