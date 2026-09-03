import 'package:flutter/material.dart';

/// 首页大厅的纯展示层，只负责转发在线和本地入口操作。
class HomePageView extends StatelessWidget {
  final VoidCallback onOnlineScan;
  final VoidCallback onOnlineList;
  final VoidCallback onLocalPage;
  final bool isOnlineLoading;
  final VoidCallback? onDiagnostics;

  const HomePageView({
    super.key,
    required this.onOnlineScan,
    required this.onOnlineList,
    required this.onLocalPage,
    this.isOnlineLoading = false,
    this.onDiagnostics,
  });

  /// 构建大厅布局和两个业务入口。
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('大厅'),
        actions: [
          IconButton(
            tooltip: '诊断日志',
            onPressed: onDiagnostics,
            icon: const Icon(Icons.bug_report_outlined),
          ),
        ],
      ),
      body: ShakeDetector(
        onShake: onDiagnostics,
        child: Stack(
          children: [
            Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 240,
                      height: 64,
                      child: FilledButton.icon(
                        onPressed: isOnlineLoading ? null : onOnlineScan,
                        icon: const Icon(Icons.qr_code_scanner_outlined),
                        label: const Text('扫码'),
                      ),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: 240,
                      height: 64,
                      child: OutlinedButton.icon(
                        onPressed: isOnlineLoading ? null : onOnlineList,
                        icon: const Icon(Icons.cloud_outlined),
                        label: const Text('全部'),
                      ),
                    ),
                    const SizedBox(height: 200),
                    // SizedBox(
                    //   width: 240,
                    //   height: 64,
                    //   child: OutlinedButton.icon(
                    //     onPressed: isOnlineLoading ? null : onLocalPage,
                    //     icon: const Icon(Icons.folder_outlined),
                    //     label: const Text('本地'),
                    //   ),
                    // ),
                  ],
                ),
              ),
            ),
            if (isOnlineLoading)
              Positioned.fill(
                child: Container(
                  color: const Color(0xCCFFFFFF),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        CircularProgressIndicator(),
                        SizedBox(height: 12),
                        Text('正在获取数据...'),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 通过快速左右交替拖动提供无需额外传感器依赖的摇一摇入口。
class ShakeDetector extends StatefulWidget {
  final VoidCallback? onShake;
  final Widget child;

  const ShakeDetector({super.key, required this.onShake, required this.child});

  @override
  State<ShakeDetector> createState() => _ShakeDetectorState();
}

class _ShakeDetectorState extends State<ShakeDetector> {
  int _changes = 0;
  int _lastDirection = 0;
  double _distance = 0;
  DateTime? _startedAt;

  /// 检测 700ms 内至少三次方向变化，触发一次诊断入口。
  void _onMove(PointerMoveEvent event) {
    final delta = event.delta.dx;
    if (delta.abs() < 12) return;
    final direction = delta.sign.toInt();
    final now = DateTime.now();
    if (_startedAt == null ||
        now.difference(_startedAt!) > const Duration(milliseconds: 700)) {
      _startedAt = now;
      _changes = 0;
      _distance = 0;
    }
    _distance += delta.abs();
    if (_lastDirection != 0 && direction != _lastDirection) _changes++;
    _lastDirection = direction;
    if (_changes >= 3 && _distance >= 120) {
      _changes = 0;
      _distance = 0;
      widget.onShake?.call();
    }
  }

  @override
  Widget build(BuildContext context) => Listener(
        onPointerMove: _onMove,
        onPointerUp: (_) {
          _lastDirection = 0;
          _startedAt = null;
        },
        child: widget.child,
      );
}
