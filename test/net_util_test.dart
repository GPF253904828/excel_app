import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:excel_app/utils/net_util.dart';
import 'package:flutter_test/flutter_test.dart';

/// 验证设备接口使用调用方提供的 URL 和 Token。
void main() {
  /// 验证设备请求日志包含配置、请求体和响应信息。
  test('prints device request and response details', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    final webhook = 'http://${server.address.address}:${server.port}';
    final logs = <String>[];

    final handledRequest = server.first.then((request) async {
      await utf8.decoder.bind(request).join();
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
              },
            },
          }),
        );
      await request.response.close();
    });

    await runZonedGuarded(
      () => DeviceApi.queryDevice(
        'P001',
        webhook: webhook,
        token: 'custom-token',
      ),
      (error, stackTrace) => fail('$error\n$stackTrace'),
      zoneSpecification: ZoneSpecification(
        print: (self, parent, zone, line) => logs.add(line),
      ),
    );
    await handledRequest;

    expect(
      logs.any(
        (line) =>
            line.contains('[DeviceApi][config]') &&
            line.contains(webhook) &&
            line.contains('custom-token'),
      ),
      isTrue,
    );
    expect(
      logs.any(
        (line) =>
            line.contains('[DeviceApi][request]') &&
            line.contains('"type":"query"') &&
            line.contains('P001'),
      ),
      isTrue,
    );
    expect(
      logs.any(
        (line) =>
            line.contains('[DeviceApi][response]') &&
            line.contains('200') &&
            line.contains('finished'),
      ),
      isTrue,
    );
  });

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

  test('sends list requests and parses all remote rows', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    Map<String, dynamic>? receivedBody;

    final handledRequest = server.first.then((request) async {
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
                'type': 'list',
                'total': 2,
                'start': 0,
                'limit': 100,
                'hasMore': false,
                'nextStart': 2,
                'rows': <Map<String, String>>[
                  <String, String>{'设备编号': 'P001', '设备名称': '设备A'},
                  <String, String>{'设备编号': 'P002', '设备名称': '设备B'},
                ],
              },
            },
          }),
        );
      await request.response.close();
    });

    final result = await DeviceApi.listDevices(
      webhook: 'http://${server.address.address}:${server.port}',
      token: 'custom-token',
    );
    await handledRequest;

    expect(
      receivedBody?['Context'],
      <String, dynamic>{
        'argv': <String, dynamic>{
          'type': 'list',
          'start': 0,
          'limit': 100,
          'includeEmpty': false,
        },
      },
    );
    expect(result.success, isTrue);
    expect(result.total, 2);
    expect(result.start, 0);
    expect(result.limit, 100);
    expect(result.hasMore, isFalse);
    expect(result.nextStart, 2);
    expect(result.rows, hasLength(2));
    expect(result.rows.first['设备编号'], 'P001');
  });
}
