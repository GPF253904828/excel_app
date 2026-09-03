import 'dart:io';

import 'package:excel_app/utils/app_log.dart';
import 'package:excel_app/utils/net_util.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';

class _SuppressingFilter extends LogFilter {
  @override
  bool shouldLog(LogEvent event) => false;
}

void main() {
  test('writes logger messages to the diagnostic file', () async {
    final directory = await Directory.systemTemp.createTemp('excel-app-log-');
    addTearDown(() => directory.delete(recursive: true));

    await AppLog.initialize(directory: directory);
    AppLog.info('network timeout: 10.200.16.15');

    final content = await AppLog.read();
    expect(content, contains('network timeout: 10.200.16.15'));
    expect(await AppLog.filePath, '${directory.path}/app.log');
  });

  test('writes logs when the default filter suppresses development output',
      () async {
    final directory = await Directory.systemTemp.createTemp('excel-app-log-');
    addTearDown(() => directory.delete(recursive: true));
    final previousFilter = Logger.defaultFilter;
    addTearDown(() => Logger.defaultFilter = previousFilter);
    Logger.defaultFilter = () => _SuppressingFilter();

    await AppLog.initialize(directory: directory);
    AppLog.info('release server startup');

    expect(await AppLog.read(), contains('release server startup'));
  });

  test('records connection failures for network diagnosis', () async {
    final directory = await Directory.systemTemp.createTemp('excel-app-log-');
    addTearDown(() => directory.delete(recursive: true));
    await AppLog.initialize(directory: directory);

    await expectLater(
      DeviceApi.queryDevice(
        'P001',
        webhook: 'http://127.0.0.1:1',
        token: 'token',
      ),
      throwsA(isA<Object>()),
    );

    expect(await AppLog.read(), contains('[DeviceApi][error]'));
  });
}
