import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:excel_app/network_tools/file_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// 验证上传完成后 FileServer 会通知页面更新已接收文件状态。
void main() {
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
    expect(page, contains('showDirectoryPicker'));

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

    server.release();
    await saveDir.delete(recursive: true);
  });
}
