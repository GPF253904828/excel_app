import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:excel_app/network_tools/file_service.dart';
import 'package:excel_app/utils/app_log.dart';
import 'package:flutter_test/flutter_test.dart';

/// 验证上传完成后 FileServer 会通知页面更新已接收文件状态。
void main() {
  test('completes initialization after the service starts listening', () async {
    final saveDir = await Directory.systemTemp.createTemp('excel_app_init_');
    addTearDown(() => saveDir.delete(recursive: true));
    final server = FileServer(port: 18082, saveDir: saveDir);
    addTearDown(server.release);

    await server.init().timeout(const Duration(seconds: 1));

    final client = HttpClient();
    final request = await client.get('127.0.0.1', 18082, '/');
    final response = await request.close();
    expect(response.statusCode, HttpStatus.ok);
    await response.drain<void>();
    client.close();
  });

  test('records a log when the service port cannot be bound', () async {
    final saveDir = await Directory.systemTemp.createTemp('excel_app_bind_');
    final logDir = await Directory.systemTemp.createTemp('excel_app_log_');
    addTearDown(() async {
      await saveDir.delete(recursive: true);
      await logDir.delete(recursive: true);
    });
    await AppLog.initialize(directory: logDir);
    final blocker = await HttpServer.bind(InternetAddress.anyIPv4, 0);
    addTearDown(blocker.close);

    final server = FileServer(port: blocker.port, saveDir: saveDir);

    await expectLater(server.init(), throwsA(isA<Object>()));

    expect(await AppLog.read(), contains('[FileServer][init] failed'));
  });

  test('notifies when a file upload is completed', () async {
    final saveDir = await Directory.systemTemp.createTemp('excel_app_test_');
    final server = FileServer(port: 18080, saveDir: saveDir);
    var notified = false;
    server.onFilesReceived = (_) => notified = true;
    server.init();

    await Future<void>.delayed(const Duration(milliseconds: 100));
    const boundary = 'test-boundary';
    final request = await HttpClient().post('127.0.0.1', 18080, '/upload');
    request.headers.contentType = ContentType('multipart', 'form-data',
        parameters: {'boundary': boundary});
    request.write('--$boundary\r\n'
        'Content-Disposition: form-data; name="file"; filename="test.txt"\r\n'
        'Content-Type: text/plain\r\n\r\n'
        'test data\r\n'
        '--$boundary--\r\n');
    final response = await request.close();
    await response.drain<void>();

    expect(notified, isTrue);
    expect(await File('${saveDir.path}/test.txt').readAsString(), 'test data');

    server.release();
    await saveDir.delete(recursive: true);
  });

  test('serves the browser page without navigation and exports queued files',
      () async {
    final saveDir = await Directory.systemTemp.createTemp('excel_app_export_');
    final server = FileServer(port: 18081, saveDir: saveDir);
    server.init();

    await Future<void>.delayed(const Duration(milliseconds: 100));
    final client = HttpClient();
    final pageRequest = await client.get('127.0.0.1', 18081, '/');
    final pageResponse = await pageRequest.close();
    final page = await utf8.decodeStream(pageResponse);
    expect(page, contains("event.preventDefault()"));
    expect(page, contains("fetch('/export'"));
    expect(page, contains('手机发送的文件会自动下载'));
    expect(page, isNot(contains('showDirectoryPicker')));
    expect(page, contains('每次只能选择一个文件'));
    expect(page, isNot(contains('multiple required')));

    server.queueExport(
        Uint8List.fromList(utf8.encode('exported')), 'edited.xls');
    final exportRequest = await client.get('127.0.0.1', 18081, '/export');
    final exportResponse = await exportRequest.close();
    expect(exportResponse.statusCode, HttpStatus.ok);
    expect(exportResponse.headers.value('content-disposition'),
        contains('edited.xls'));
    expect(await utf8.decodeStream(exportResponse), 'exported');

    final emptyRequest = await client.get('127.0.0.1', 18081, '/export');
    final emptyResponse = await emptyRequest.close();
    expect(emptyResponse.statusCode, HttpStatus.noContent);
    await emptyResponse.drain<void>();

    server.queueExport(
      Uint8List.fromList([0x50, 0x4B]),
      'A.zip',
      contentType: 'application/zip',
    );
    final zipRequest = await client.get('127.0.0.1', 18081, '/export');
    final zipResponse = await zipRequest.close();
    expect(zipResponse.statusCode, HttpStatus.ok);
    expect(zipResponse.headers.contentType?.mimeType, 'application/zip');
    expect(zipResponse.headers.value('content-disposition'), contains('A.zip'));
    await zipResponse.drain<void>();

    server.release();
    await saveDir.delete(recursive: true);
  });
}
