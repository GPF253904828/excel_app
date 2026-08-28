import 'dart:convert';
import 'dart:io';

import 'package:excel_app/utils/net_util.dart';
import 'package:flutter_test/flutter_test.dart';

/// 验证设备接口使用调用方提供的 URL 和 Token。
void main() {
  test('uses the supplied URL and token for device requests', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    String? receivedToken;
    Map<String, dynamic>? receivedBody;

    final handledRequest = server.first.then((request) async {
      receivedToken = request.headers.value('AirScript-Token');
      receivedBody = jsonDecode(
        await utf8.decoder.bind(request).join(),
      ) as Map<String, dynamic>;
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.json
        ..write(
          jsonEncode(<String, dynamic>{
            'status': 'finished',
            'data': <String, dynamic>{
              'result': <String, dynamic>{
                'success': true,
                'type': 'query',
                'device_no': 'P001',
                'data': <String, dynamic>{'设备编号': 'P001'},
              },
            },
          }),
        );
      await request.response.close();
    });

    final result = await DeviceApi.queryDevice(
      'P001',
      webhook: 'http://${server.address.address}:${server.port}',
      token: 'custom-token',
    );
    await handledRequest;

    expect(result.success, isTrue);
    expect(receivedToken, 'custom-token');
    expect(
      receivedBody?['Context'],
      <String, dynamic>{
        'argv': <String, dynamic>{'type': 'query', 'device_no': 'P001'},
      },
    );
  });
}
