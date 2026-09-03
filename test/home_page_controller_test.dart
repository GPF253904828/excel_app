import 'dart:io';

import 'package:excel_app/home_page_controller.dart';
import 'package:excel_app/log/app_log.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('does not report running when the service cannot bind its port',
      () async {
    final logDirectory =
        await Directory.systemTemp.createTemp('excel-app-controller-log-');
    addTearDown(() => logDirectory.delete(recursive: true));
    await AppLog.initialize(directory: logDirectory);
    const pathProviderChannel =
        MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance!.defaultBinaryMessenger
        .setMockMethodCallHandler(
      pathProviderChannel,
      (call) async => logDirectory.path,
    );
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance!.defaultBinaryMessenger
          .setMockMethodCallHandler(pathProviderChannel, null);
    });
    final blocker = await HttpServer.bind(InternetAddress.anyIPv4, 0);
    addTearDown(blocker.close);

    final controller = HomePageController(port: blocker.port);
    addTearDown(controller.dispose);

    await controller.startServer();

    expect(controller.isRunning, isFalse);
    expect(controller.status, startsWith('启动失败'));
  });

  test('captures network information when the file service starts', () async {
    final logDirectory =
        await Directory.systemTemp.createTemp('excel-app-controller-log-');
    addTearDown(() => logDirectory.delete(recursive: true));
    await AppLog.initialize(directory: logDirectory);
    const pathProviderChannel =
        MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance!.defaultBinaryMessenger
        .setMockMethodCallHandler(
      pathProviderChannel,
      (call) async => logDirectory.path,
    );
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance!.defaultBinaryMessenger
          .setMockMethodCallHandler(pathProviderChannel, null);
    });

    final controller = HomePageController(port: 0);
    addTearDown(controller.dispose);

    await controller.startServer();

    expect(await AppLog.read(), contains('[Diagnostics][network]'));
    expect(controller.networkInfo, contains('Wi-Fi 网卡:'));
  });
}
