import 'dart:io';
import 'dart:ui' as ui;

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

/// 表示一条可生成二维码的设备记录。
class QrDevice {
  final String deviceNumber;
  final String deviceName;
  final String deviceModel;

  const QrDevice(
    this.deviceNumber,
    this.deviceName, [
    this.deviceModel = '',
  ]);

  @override
  bool operator ==(Object other) =>
      other is QrDevice &&
      other.deviceNumber == deviceNumber &&
      other.deviceName == deviceName &&
      other.deviceModel == deviceModel;

  @override
  int get hashCode => Object.hash(deviceNumber, deviceName, deviceModel);
}

/// 从表格中提取同时包含设备编号和设备名称的有效记录，并读取设备型号。
List<QrDevice> extractQrDevices(
  List<String> headers,
  List<List<String>> rows,
) {
  final numberIndex = headers.indexOf('设备编号');
  final nameIndex = headers.indexOf('设备名称');
  final modelIndex = headers.indexOf('设备型号');
  if (numberIndex < 0 || nameIndex < 0) return [];

  final devices = <QrDevice>[];
  for (final row in rows) {
    if (numberIndex >= row.length || nameIndex >= row.length) continue;
    final number = row[numberIndex].trim();
    final name = row[nameIndex].trim();
    if (number.isEmpty || name.isEmpty) continue;
    final model = modelIndex >= 0 && modelIndex < row.length
        ? row[modelIndex].trim()
        : '';
    devices.add(QrDevice(number, name, model));
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
  static Future<ui.Image>? _brandMarkFuture;

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

  /// 使用 qr_flutter 绘制紧凑双栏二维码，并合成设备信息与公司名称。
  Future<Uint8List> _renderPng(QrDevice device) async {
    const width = 640.0;
    const height = 260.0;
    const qrOffset = Offset(30, 24);
    const qrSize = 172.0;
    final brandMark = await _loadBrandMark();
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawColor(Colors.white, BlendMode.src);

    canvas.save();
    canvas.translate(qrOffset.dx, qrOffset.dy);
    QrPainter(
      data: device.deviceNumber,
      version: QrVersions.auto,
      gapless: true,
      errorCorrectionLevel: QrErrorCorrectLevel.H,
    ).paint(canvas, const Size(qrSize, qrSize));
    canvas.restore();
    _paintBrandMark(canvas, brandMark, qrOffset, qrSize);
    var offsetY = 12.0;
    _paintDeviceInfo(
      canvas,
      '设备编号',
      device.deviceNumber,
      Offset(250, 34 - offsetY),
    );
    _paintDeviceInfo(
        canvas, '设备名称', device.deviceName, Offset(250, 96 - offsetY));
    _paintDeviceInfo(
      canvas,
      '设备型号',
      device.deviceModel.isEmpty ? '未填写' : device.deviceModel,
      Offset(250, 158 - offsetY),
    );
    _paintText(
      canvas,
      '其他信息请扫描查看',
      const Offset(48, 207),
      style: const TextStyle(
        color: Colors.black54,
        fontSize: 14,
        height: 1.2,
      ),
      maxWidth: qrSize,
      textAlign: TextAlign.center,
    );
    _paintText(
      canvas,
      '北京雅康博生物科技有限公司',
      Offset(250, 226 - offsetY),
      style: const TextStyle(
        color: Colors.black54,
        fontSize: 14,
        height: 1.2,
      ),
      maxWidth: 360,
    );

    final picture = recorder.endRecording();
    final image = await picture.toImage(width.toInt(), height.toInt());
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    picture.dispose();
    if (data == null) throw StateError('二维码图片生成失败');
    return data.buffer.asUint8List();
  }

  /// 缓存并解码二维码中心使用的官方品牌标识。
  Future<ui.Image> _loadBrandMark() => _brandMarkFuture ??= _decodeBrandMark();

  /// 将官方完整 Logo 解码为适合二维码中心区域的位图。
  Future<ui.Image> _decodeBrandMark() async {
    final data = await rootBundle.load('assets/branding/acbio_logo.png');
    final codec = await ui.instantiateImageCodec(
      data.buffer.asUint8List(),
      targetHeight: 28,
    );
    final frame = await codec.getNextFrame();
    codec.dispose();
    return frame.image;
  }

  /// 在二维码中心绘制白色留白和官方完整 Logo，保持二维码可识别性。
  void _paintBrandMark(
    Canvas canvas,
    ui.Image brandMark,
    Offset qrOffset,
    double qrSize,
  ) {
    final center = Offset(
      qrOffset.dx + qrSize / 2,
      qrOffset.dy + qrSize / 2,
    );
    final cover = RRect.fromRectAndRadius(
      Rect.fromCenter(center: center, width: 76, height: 42),
      const Radius.circular(5),
    );
    canvas.drawRRect(cover, Paint()..color = Colors.white);

    const markHeight = 28.0;
    final markWidth = markHeight * brandMark.width / brandMark.height;
    final destination = Rect.fromCenter(
      center: center,
      width: markWidth,
      height: markHeight,
    );
    canvas.drawImageRect(
      brandMark,
      Rect.fromLTWH(
          0, 0, brandMark.width.toDouble(), brandMark.height.toDouble()),
      destination,
      Paint()..filterQuality = FilterQuality.high,
    );
  }

  /// 绘制右侧设备字段及其分隔线，保持三项信息的统一层级。
  void _paintDeviceInfo(
    Canvas canvas,
    String label,
    String value,
    Offset offset,
  ) {
    const maxWidth = 360.0;
    _paintText(
      canvas,
      label,
      offset,
      style: const TextStyle(
        color: Colors.black54,
        fontSize: 13,
        height: 1.2,
      ),
      maxWidth: maxWidth,
    );
    _paintText(
      canvas,
      value,
      Offset(offset.dx, offset.dy + 20),
      style: const TextStyle(
        color: Colors.black,
        fontSize: 20,
        fontWeight: FontWeight.w500,
        height: 1.2,
      ),
      maxWidth: maxWidth,
    );
    canvas.drawLine(
      Offset(offset.dx, offset.dy + 52),
      Offset(offset.dx + maxWidth, offset.dy + 52),
      Paint()..color = Colors.black12,
    );
  }

  /// 将标签文本绘制到固定区域内，避免长内容挤出画布。
  void _paintText(
    Canvas canvas,
    String text,
    Offset offset, {
    TextStyle style = const TextStyle(
      color: Colors.black,
      fontSize: 24,
      height: 1.2,
    ),
    double maxWidth = 365,
    TextAlign textAlign = TextAlign.left,
    int maxLines = 1,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: style,
      ),
      textDirection: TextDirection.ltr,
      textAlign: textAlign,
      maxLines: maxLines,
      ellipsis: '...',
    )..layout(maxWidth: maxWidth);
    painter.paint(canvas, offset);
  }
}
