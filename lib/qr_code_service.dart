import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

/// 表示一条可生成二维码的设备记录。
class QrDevice {
  final String deviceNumber;
  final String deviceName;

  const QrDevice(this.deviceNumber, this.deviceName);

  @override
  bool operator ==(Object other) =>
      other is QrDevice &&
      other.deviceNumber == deviceNumber &&
      other.deviceName == deviceName;

  @override
  int get hashCode => Object.hash(deviceNumber, deviceName);
}

/// 从表格中提取同时包含设备编号和设备名称的有效记录。
List<QrDevice> extractQrDevices(
  List<String> headers,
  List<List<String>> rows,
) {
  final numberIndex = headers.indexOf('设备编号');
  final nameIndex = headers.indexOf('设备名称');
  if (numberIndex < 0 || nameIndex < 0) return [];

  final devices = <QrDevice>[];
  for (final row in rows) {
    if (numberIndex >= row.length || nameIndex >= row.length) continue;
    final number = row[numberIndex].trim();
    final name = row[nameIndex].trim();
    if (number.isEmpty || name.isEmpty) continue;
    devices.add(QrDevice(number, name));
  }
  return devices;
}

/// 清理设备文件名并为重复名称追加序号。
String qrFileName(QrDevice device, Set<String> usedNames) {
  final baseName = '${device.deviceNumber}${device.deviceName}'
      .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1F]'), '_');
  final base = baseName.isEmpty ? 'qr_code' : baseName;
  var fileName = '$base.png';
  var suffix = 2;
  while (usedNames.contains(fileName)) {
    fileName = '${base}_$suffix.png';
    suffix++;
  }
  usedNames.add(fileName);
  return fileName;
}

/// 生成二维码图片并将图片打包为 ZIP。
class QrCodeService {
  final Directory outputDirectory;

  const QrCodeService(this.outputDirectory);

  /// 清理旧图片并为设备记录生成新的 PNG 文件。
  Future<List<File>> generate(List<QrDevice> devices) async {
    await outputDirectory.create(recursive: true);
    for (final entity in outputDirectory.listSync()) {
      if (entity is File && entity.path.toLowerCase().endsWith('.png')) {
        await entity.delete();
      }
    }

    final usedNames = <String>{};
    final files = <File>[];
    for (final device in devices) {
      final file =
          File('${outputDirectory.path}/${qrFileName(device, usedNames)}');
      await file.writeAsBytes(await _renderPng(device), flush: true);
      files.add(file);
    }
    return files;
  }

  /// 将最近生成的 PNG 文件压缩为 ZIP 字节流。
  Future<Uint8List> zip(List<File> files) async {
    final archive = Archive();
    for (final file in files) {
      final bytes = await file.readAsBytes();
      archive.addFile(
          ArchiveFile(file.uri.pathSegments.last, bytes.length, bytes));
    }
    final encoded = ZipEncoder().encode(archive);
    if (encoded == null) throw StateError('二维码压缩失败');
    return Uint8List.fromList(encoded);
  }

  /// 使用 qr_flutter 绘制二维码，并合成右侧的设备编号和名称。
  Future<Uint8List> _renderPng(QrDevice device) async {
    const width = 640.0;
    const height = 240.0;
    const qrSize = 200.0;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawColor(Colors.white, BlendMode.src);

    canvas.save();
    canvas.translate(20, 20);
    QrPainter(
      data: device.deviceNumber,
      version: QrVersions.auto,
      gapless: true,
    ).paint(canvas, const Size(qrSize, qrSize));
    canvas.restore();

    _paintText(canvas, '设备编号: ${device.deviceNumber}', const Offset(250, 55));
    _paintText(canvas, '设备名称: ${device.deviceName}', const Offset(250, 135));

    final picture = recorder.endRecording();
    final image = await picture.toImage(width.toInt(), height.toInt());
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    picture.dispose();
    if (data == null) throw StateError('二维码图片生成失败');
    return data.buffer.asUint8List();
  }

  /// 将设备文本绘制到图片右侧并限制在固定区域内。
  void _paintText(Canvas canvas, String text, Offset offset) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(
          color: Colors.black,
          fontSize: 24,
          height: 1.2,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 2,
      ellipsis: '...',
    )..layout(maxWidth: 365);
    painter.paint(canvas, offset);
  }
}
