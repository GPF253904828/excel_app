import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// 返回扫描结果中第一个去除首尾空白后的有效原始值。
String? firstScanValue(BarcodeCapture capture) {
  for (final barcode in capture.barcodes) {
    final value = barcode.rawValue?.trim();
    if (value != null && value.isNotEmpty) return value;
  }
  return null;
}

/// 提供设备二维码扫描页面，并将首个有效编码返回给调用方。
class ScannerPage extends StatefulWidget {
  const ScannerPage({super.key});

  @override
  State<ScannerPage> createState() => _ScannerPageState();
}

class _ScannerPageState extends State<ScannerPage> {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  bool _completed = false;

  /// 处理扫描事件，只接受首个有效编码并结束相机扫描。
  void _handleDetection(BarcodeCapture capture) {
    if (_completed) return;

    final value = firstScanValue(capture);
    if (value == null) return;

    _completed = true;
    _controller.stop();
    if (!mounted) return;
    Navigator.pop(context, value);
  }

  /// 将扫码启动错误转换为可读提示，并提供返回操作。
  Widget _buildScannerError(
    BuildContext context,
    MobileScannerException error,
    Widget? child,
  ) {
    final permissionDenied =
        error.errorCode == MobileScannerErrorCode.permissionDenied;
    final message =
        permissionDenied ? '相机权限被拒绝，请在系统设置中允许相机权限。' : '相机初始化失败，请检查设备后重试。';

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('返回'),
            ),
          ],
        ),
      ),
    );
  }

  /// 返回上一页，不带扫描结果。
  void _cancel() {
    Navigator.pop(context);
  }

  /// 释放扫码控制器。
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// 构建相机预览和取消操作。
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('扫描设备编码'),
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _handleDetection,
            errorBuilder: _buildScannerError,
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: SafeArea(
              minimum: const EdgeInsets.all(16),
              child: ElevatedButton(
                onPressed: _cancel,
                child: const Text('取消'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
