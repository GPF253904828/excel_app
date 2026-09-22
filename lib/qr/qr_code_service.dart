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

  /// 官方 Logo 原图中“AccBio”字标的裁剪范围（比例，去除底部文字与四周留白）。
  static const Rect _brandMarkCrop = Rect.fromLTRB(
    345 / 3303,
    39 / 1461,
    2900 / 3303,
    875 / 1461,
  );

  const QrCodeService(this.outputDirectory);

  /// 清理旧图片并为设备记录生成新的 PNG 文件。
  Future<List<File>> generate(List<QrDevice> devices) async {
    await clear();

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

  /// 删除输出目录中已有的二维码 PNG，保留目录内的其他文件。
  Future<void> clear() async {
    await outputDirectory.create(recursive: true);
    for (final entity in outputDirectory.listSync()) {
      if (entity is File && entity.path.toLowerCase().endsWith('.png')) {
        await entity.delete();
      }
    }
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

  /// 使用 qr_flutter 绘制高分辨率紧凑双栏二维码，并合成设备信息。
  Future<Uint8List> _renderPng(QrDevice device) async {
    const imageScale = 3.0;
    const width = 1920.0;
    const height = 738.0;
    const qrOffset = Offset(30, 31);
    const qrSize = 172.0;
    final brandMark = await _loadBrandMark();
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawColor(Colors.white, BlendMode.src);
    canvas.scale(imageScale);
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
    // 右侧四行信息：行高与上下留白对称，字号在可用空间内取最大。
    const infoLeft = 220.0;
    const infoTop = 6.0;
    const infoRowHeight = 55.0;
    const infoWidth = 390.0;
    _paintInfoRow(
      canvas,
      '设备编号:',
      device.deviceNumber,
      const Rect.fromLTWH(infoLeft, infoTop, infoWidth, infoRowHeight),
    );
    _paintInfoRow(
      canvas,
      '设备名称:',
      device.deviceName,
      const Rect.fromLTWH(
          infoLeft, infoTop + infoRowHeight, infoWidth, infoRowHeight),
    );
    _paintInfoRow(
      canvas,
      '设备型号:',
      device.deviceModel.isEmpty ? '未填写' : device.deviceModel,
      const Rect.fromLTWH(
          infoLeft, infoTop + infoRowHeight * 2, infoWidth, infoRowHeight),
    );
    _paintFittedText(
      canvas,
      '其他信息请扫码查看2',
      const Rect.fromLTWH(
          infoLeft, infoTop + infoRowHeight * 3, infoWidth, infoRowHeight),
      maxFontSize: 20,
      color: Colors.black87,
      fontWeight: FontWeight.w500,
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

  /// 将官方 Logo 解码为高分辨率位图，供中心字标裁剪使用。
  Future<ui.Image> _decodeBrandMark() async {
    final data = await rootBundle.load('assets/branding/acbio_logo.png');
    final codec = await ui.instantiateImageCodec(
      data.buffer.asUint8List(),
      targetHeight: 480,
    );
    final frame = await codec.getNextFrame();
    codec.dispose();
    return frame.image;
  }

  /// 在二维码中心绘制白色留白与放大后的品牌字标，兼顾可读性与识别率。
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
    // 留白约占二维码面积 16.7%，在 H 级纠错范围内仍可正常识别。
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: center, width: 112, height: 44),
        const Radius.circular(6),
      ),
      Paint()..color = Colors.white,
    );

    final source = Rect.fromLTRB(
      _brandMarkCrop.left * brandMark.width,
      _brandMarkCrop.top * brandMark.height,
      _brandMarkCrop.right * brandMark.width,
      _brandMarkCrop.bottom * brandMark.height,
    );
    const markWidth = 100.0;
    canvas.drawImageRect(
      brandMark,
      source,
      Rect.fromCenter(
        center: center,
        width: markWidth,
        height: markWidth * source.height / source.width,
      ),
      Paint()..filterQuality = FilterQuality.high,
    );
  }

  /// 在右侧单行内绘制标签与值，并绘制行分隔线。
  void _paintInfoRow(
    Canvas canvas,
    String label,
    String value,
    Rect rect, {
    double labelWidth = 96.0,
  }) {
    // 标签列固定宽度，取值列占据剩余空间，两列在同一行内垂直居中。
    _paintFittedText(
      canvas,
      label,
      Rect.fromLTWH(rect.left, rect.top, labelWidth, rect.height),
      maxFontSize: 32,
      color: Colors.black87,
      fontWeight: FontWeight.w500,
    );
    _paintFittedText(
      canvas,
      value,
      Rect.fromLTWH(rect.left + labelWidth, rect.top, rect.width - labelWidth,
          rect.height),
      maxFontSize: 32,
    );
    canvas.drawLine(
      Offset(rect.left, rect.bottom - 6),
      Offset(rect.right, rect.bottom - 6),
      Paint()..color = Colors.black12,
    );
  }

  /// 在给定区域内绘制单行文本，字号从最大值逐级缩小直到内容不溢出。
  void _paintFittedText(
    Canvas canvas,
    String text,
    Rect rect, {
    required double maxFontSize,
    Color color = Colors.black,
    FontWeight fontWeight = FontWeight.w600,
    double minFontSize = 16,
  }) {
    var fontSize = maxFontSize;
    late TextPainter painter;
    while (true) {
      painter = TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            color: color,
            fontSize: fontSize,
            fontWeight: fontWeight,
            height: 1.2,
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '...',
      )..layout(maxWidth: rect.width);
      if (fontSize <= minFontSize || !painter.didExceedMaxLines) break;
      fontSize -= 1;
    }
    painter.paint(
      canvas,
      Offset(rect.left, rect.top + (rect.height - painter.height) / 2),
    );
  }
}
