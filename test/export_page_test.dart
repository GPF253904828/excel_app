import 'dart:typed_data';

import 'package:excel_app/export_page.dart';
import 'package:excel_app/home_page_controller.dart';
import 'package:excel_app/local_page_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _TrackingHomePageController extends HomePageController {
  bool startCalled = false;

  _TrackingHomePageController() : super(port: 8080);

  @override
  Future<void> startServer() async {
    startCalled = true;
  }

  @override
  bool get isRunning => true;

  @override
  String get status => '运行中';

  @override
  String? get localIp => '192.168.1.10';

  @override
  String? get networkInfo => 'Wi-Fi 网卡: wlan0\nIPv4: 192.168.1.10';
}

/// 验证导出页复用统一文件服务的状态和控制入口。
void main() {
  testWidgets('starts the file service when the export page opens',
      (tester) async {
    final controller = _TrackingHomePageController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: ExportPage(
          controller: controller,
          archive: Uint8List.fromList(<int>[0x50, 0x4B]),
          filename: '二维码合计.zip',
        ),
      ),
    );
    await tester.pump();

    expect(controller.startCalled, isTrue);
  });

  testWidgets('renders export service controls', (tester) async {
    final controller = _TrackingHomePageController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: ExportPage(
          controller: controller,
          archive: Uint8List.fromList(<int>[0x50, 0x4B]),
          filename: '二维码合计.zip',
        ),
      ),
    );

    expect(find.byKey(const Key('export-qr-archive')), findsOneWidget);
    expect(find.text('状态: 运行中'), findsOneWidget);
    expect(find.text('启动服务'), findsOneWidget);
    expect(find.text('Wi-Fi 网卡: wlan0\nIPv4: 192.168.1.10'), findsOneWidget);
  });

  testWidgets('uses an export-specific network hint', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: LocalPageView(
          title: '导出',
          status: '运行中',
          localIp: '192.168.1.10',
          port: 8080,
          isRunning: true,
          hasFiles: false,
          networkHint: '在电脑浏览器中打开上面的地址即可接收导出文件',
          showFileManagement: false,
          onStart: () {},
          onStop: () {},
          onOpenFiles: () {},
        ),
      ),
    );

    expect(find.text('在电脑浏览器中打开上面的地址即可接收导出文件'), findsOneWidget);
  });

  testWidgets('shows current wifi information in the secondary area',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: LocalPageView(
          title: '导出',
          status: '运行中',
          localIp: '10.200.16.15',
          port: 8080,
          isRunning: true,
          hasFiles: false,
          networkInfo: 'Wi-Fi 网卡: wlan0\nIPv4: 10.200.16.15',
          showFileManagement: false,
          onStart: () {},
          onStop: () {},
          onOpenFiles: () {},
        ),
      ),
    );

    expect(find.text('Wi-Fi 网卡: wlan0\nIPv4: 10.200.16.15'), findsOneWidget);
  });

  testWidgets('shares the QR archive through the configured callback',
      (tester) async {
    final controller = _TrackingHomePageController();
    addTearDown(controller.dispose);
    final archive = Uint8List.fromList(<int>[0x50, 0x4B]);
    Uint8List? sharedArchive;
    String? sharedFilename;

    await tester.pumpWidget(
      MaterialApp(
        home: ExportPage(
          controller: controller,
          archive: archive,
          filename: '二维码合计.zip',
          onShare: (bytes, filename) async {
            sharedArchive = bytes;
            sharedFilename = filename;
          },
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('share-qr-archive')), findsOneWidget);

    await tester.tap(find.byKey(const Key('share-qr-archive')));
    await tester.pumpAndSettle();

    expect(sharedArchive, same(archive));
    expect(sharedFilename, '二维码合计.zip');
    expect(find.text('已分享 二维码合计.zip'), findsOneWidget);
  });

  testWidgets('shows an error when sharing the QR archive fails',
      (tester) async {
    final controller = _TrackingHomePageController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: ExportPage(
          controller: controller,
          archive: Uint8List.fromList(<int>[0x50, 0x4B]),
          filename: '二维码合计.zip',
          onShare: (_, __) async {
            throw StateError('share unavailable');
          },
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('share-qr-archive')));
    await tester.pumpAndSettle();

    expect(find.textContaining('分享失败: Bad state: share unavailable'),
        findsOneWidget);
  });
}
