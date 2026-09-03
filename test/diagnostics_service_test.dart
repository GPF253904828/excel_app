import 'dart:io';

import 'package:excel_app/log/diagnostics_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('collects device and network diagnostics', () async {
    final diagnostics = await collectDiagnostics(
      serverStatus: '运行中',
      serverPort: 8080,
      serverLocalIp: '192.168.1.10',
    );

    expect(diagnostics, contains('operatingSystem'));
    expect(diagnostics, contains('networkInterfaces'));
    expect(diagnostics, contains('运行中'));
    expect(diagnostics, contains('8080'));
    expect(diagnostics, contains('192.168.1.10'));
  });

  test('creates a timestamped zip containing app.log', () async {
    final directory = await Directory.systemTemp.createTemp('excel-app-zip-');
    addTearDown(() => directory.delete(recursive: true));
    final logFile = File('${directory.path}/app.log')
      ..writeAsStringSync('network timeout');

    final zip = await createDiagnosticsZip(logFile, directory: directory);

    expect(zip.uri.pathSegments.last,
        matches(RegExp(r'^diagnostic_\d{8}_\d{6}\.zip$')));
    expect(zip.lengthSync(), greaterThan(20));
  });
}
