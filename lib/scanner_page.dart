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
  /// 页面主动退出只调用一次 stop；卸载后的 dispose/stop 由 MobileScanner
  /// 内部负责，属于插件行为，页面无法避免也不再额外包装 controller。
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  bool _completed = false;

  /// 停止扫描并只执行一次返回，可选地携带扫描结果。
  Future<void> _finish([String? value]) async {
    if (_completed) return;
    _completed = true;

    try {
      await _controller.stop();
    } catch (_) {
      // 停止相机失败不应阻止页面返回。
    }
    if (!mounted) return;
    Navigator.pop(context, value);
  }

  /// 处理扫描事件，只接受首个有效编码并结束相机扫描。
  Future<void> _handleDetection(BarcodeCapture capture) async {
    if (_completed) return;

    final value = firstScanValue(capture);
    if (value == null) return;
    await _finish(value);
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
              onPressed: _finish,
              child: const Text('返回'),
            ),
          ],
        ),
      ),
    );
  }

  /// 返回上一页，不带扫描结果。
  Future<void> _cancel() => _finish();

  /// 拦截系统返回，确保它与按钮和扫码成功共用同一退出流程。
  Future<bool> _handleWillPop() async {
    await _finish();
    return false;
  }

  /// 构建相机预览和取消操作。
  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: _handleWillPop,
      child: Scaffold(
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
      ),
    );
  }
}
