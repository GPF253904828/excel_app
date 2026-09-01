import 'dart:io';
import 'dart:ui' as ui;

import 'package:archive/archive.dart';
import 'package:excel_app/qr_code_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// 判断二维码 PNG 是否包含官方标识的紫色色素。
Future<bool> _hasBrandPurplePixel(ui.Image image) async {
  final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  if (bytes == null) return false;

  for (var offset = 0; offset < bytes.lengthInBytes; offset += 4) {
    final red = bytes.getUint8(offset);
    final green = bytes.getUint8(offset + 1);
    final blue = bytes.getUint8(offset + 2);
    if (red >= 110 &&
        red <= 180 &&
        green <= 110 &&
        blue >= 110 &&
        blue <= 190) {
      return true;
    }
  }
  return false;
}

/// 判断二维码 PNG 是否包含官方完整 Logo 的黄色像素。
Future<bool> _hasBrandYellowPixel(ui.Image image) async {
  final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  if (bytes == null) return false;

  for (var offset = 0; offset < bytes.lengthInBytes; offset += 4) {
    final red = bytes.getUint8(offset);
    final green = bytes.getUint8(offset + 1);
    final blue = bytes.getUint8(offset + 2);
    if (red >= 180 && green >= 120 && blue <= 100) return true;
  }
  return false;
}

/// 判断右下品牌文字区域是否仍包含深色文字像素。
Future<bool> _hasCompanyTextPixel(ui.Image image) async {
  final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  if (bytes == null) return false;

  final startX = (image.width * .39).floor();
  final endX = (image.width * .98).floor();
  final startY = (image.height * .80).floor();
  final endY = (image.height * .95).floor();
  for (var y = startY; y < endY; y++) {
    for (var x = startX; x < endX; x++) {
      final offset = (y * image.width + x) * 4;
      if (bytes.getUint8(offset) < 220 &&
          bytes.getUint8(offset + 1) < 220 &&
          bytes.getUint8(offset + 2) < 220) {
        return true;
      }
    }
  }
  return false;
}

/// 返回 PNG 中最上和最下的非白色内容行，用于校验垂直留白。
Future<List<int>> _contentRowBounds(ui.Image image) async {
  final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  if (bytes == null) return [];

  var first = image.height;
  var last = -1;
  for (var y = 0; y < image.height; y++) {
    for (var x = 0; x < image.width; x++) {
      final offset = (y * image.width + x) * 4;
      if (bytes.getUint8(offset) < 245 ||
          bytes.getUint8(offset + 1) < 245 ||
          bytes.getUint8(offset + 2) < 245) {
        first = first < y ? first : y;
        last = last > y ? last : y;
        break;
      }
    }
  }
  return [first, last];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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

  test('extracts the device model when the table provides it', () {
    final devices = extractQrDevices(
      ['设备编号', '设备名称', '设备型号'],
      [
        ['P001', '设备A', '型号A'],
      ],
    );

    expect(devices.single.deviceModel, '型号A');
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

  test('uses the high-resolution compact layout in generated PNGs', () async {
    final directory = await Directory.systemTemp.createTemp('qr_layout_test_');
    final service = QrCodeService(directory);

    try {
      final files = await service.generate(const [QrDevice('P001', '设备A')]);
      final codec = await ui.instantiateImageCodec(
        await files.single.readAsBytes(),
      );
      final frame = await codec.getNextFrame();

      expect(frame.image.width, 1920);
      expect(frame.image.height, 738);
      frame.image.dispose();
      codec.dispose();
    } finally {
      await directory.delete(recursive: true);
    }
  });

  test('keeps equal top and bottom content padding in generated QR PNGs',
      () async {
    final directory = await Directory.systemTemp.createTemp('qr_padding_test_');
    final service = QrCodeService(directory);

    try {
      final files = await service.generate(const [QrDevice('P001', '设备A')]);
      final codec = await ui.instantiateImageCodec(
        await files.single.readAsBytes(),
      );
      final frame = await codec.getNextFrame();
      final bounds = await _contentRowBounds(frame.image);
      final topPadding = bounds.first;
      final bottomPadding = frame.image.height - 1 - bounds.last;

      expect(topPadding, closeTo(bottomPadding, 4));
      frame.image.dispose();
      codec.dispose();
    } finally {
      await directory.delete(recursive: true);
    }
  });

  test('omits the company name from generated QR PNGs', () async {
    final directory = await Directory.systemTemp.createTemp('qr_company_test_');
    final service = QrCodeService(directory);

    try {
      final files = await service.generate(const [QrDevice('P001', '设备A')]);
      final codec = await ui.instantiateImageCodec(
        await files.single.readAsBytes(),
      );
      final frame = await codec.getNextFrame();

      expect(await _hasCompanyTextPixel(frame.image), isFalse);
      frame.image.dispose();
      codec.dispose();
    } finally {
      await directory.delete(recursive: true);
    }
  });

  test('embeds the full-color official logo in generated QR PNGs', () async {
    final directory = await Directory.systemTemp.createTemp('qr_brand_test_');
    final service = QrCodeService(directory);

    try {
      final files = await service.generate(const [QrDevice('P001', '设备A')]);
      final codec = await ui.instantiateImageCodec(
        await files.single.readAsBytes(),
      );
      final frame = await codec.getNextFrame();

      expect(await _hasBrandPurplePixel(frame.image), isTrue);
      expect(await _hasBrandYellowPixel(frame.image), isTrue);
      frame.image.dispose();
      codec.dispose();
    } finally {
      await directory.delete(recursive: true);
    }
  });
}
