// ignore_for_file: avoid_print

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:excel_app/utils/app_log.dart';

/// 设备表脚本接口封装（对应 WPS 端 JS 脚本的 query/modify/add/delete 四类操作）
class DeviceApi {
  DeviceApi._(); // 工具类，禁止实例化

  /// 统一调用脚本接口并返回 AirScript 的业务结果对象。
  static Future<Map<String, dynamic>> _invokeRaw(
    Map<String, dynamic> argv, {
    required String webhook,
    required String token,
  }) async {
    final requestBody = <String, dynamic>{
      'Context': {'argv': argv},
    };
    final encodedRequestBody = jsonEncode(requestBody);
    print('[DeviceApi][config] webhook=$webhook token=$token');
    AppLog.info(
        '[DeviceApi][config] webhook=$webhook token=${_maskToken(token)}');
    print(
      '[DeviceApi][request] method=POST url=$webhook '
      'headers={AirScript-Token: $token, Content-Type: application/json} '
      'body=$encodedRequestBody',
    );
    AppLog.info(
        '[DeviceApi][request] method=POST url=$webhook body=$encodedRequestBody');

    late http.Response resp;
    try {
      resp = await http.post(
        Uri.parse(webhook),
        headers: {
          'AirScript-Token': token,
          'Content-Type': 'application/json',
        },
        body: encodedRequestBody,
      );
    } catch (error, stackTrace) {
      AppLog.error(
          '[DeviceApi][error] request failed url=$webhook', error, stackTrace);
      rethrow;
    }
    final responseBody = utf8.decode(resp.bodyBytes, allowMalformed: true);
    print(
      '[DeviceApi][response] status=${resp.statusCode} '
      'headers=${resp.headers} body=$responseBody',
    );
    AppLog.info(
        '[DeviceApi][response] status=${resp.statusCode} body=$responseBody');

    if (resp.statusCode != 200) {
      throw DeviceApiException('HTTP ${resp.statusCode}: $responseBody');
    }

    final json = jsonDecode(responseBody) as Map<String, dynamic>;

    // 脚本执行失败（语法错误、异常中断等）
    if ((json['status'] ?? '') != 'finished' || (json['error'] ?? '') != '') {
      throw DeviceApiException('脚本执行异常: ${json['error']}');
    }

    // 脚本 return 的对象在 data.result
    final data = json['data'] as Map<String, dynamic>? ?? {};
    final result = (data['result'] as Map<String, dynamic>?) ?? {};
    return result;
  }

  /// 脱敏保存接口令牌，避免诊断日志暴露完整凭据。
  static String _maskToken(String token) {
    if (token.length <= 4) return '****';
    return '${token.substring(0, 2)}****${token.substring(token.length - 2)}';
  }

  /// 统一调用脚本接口并解析单条设备操作结果。
  static Future<DeviceResult> _invoke(
    Map<String, dynamic> argv, {
    required String webhook,
    required String token,
  }) async {
    return DeviceResult.fromJson(
      await _invokeRaw(argv, webhook: webhook, token: token),
    );
  }

  /// 按设备编号查询并返回脚本中的完整行数据。
  static Future<DeviceResult> queryDevice(
    String deviceNo, {
    required String webhook,
    required String token,
  }) {
    return _invoke(
      <String, dynamic>{'type': 'query', 'device_no': deviceNo},
      webhook: webhook,
      token: token,
    );
  }

  /// 回写真实表头字段并返回更新后的完整行数据。
  static Future<DeviceResult> modifyDevice(
    String deviceNo,
    Map<String, dynamic> data, {
    required String webhook,
    required String token,
  }) {
    return _invoke(
      <String, dynamic>{
        'type': 'modify',
        'device_no': deviceNo,
        'data': data,
      },
      webhook: webhook,
      token: token,
    );
  }

  /// 将真实表头字段追加为表格末尾的新行。
  static Future<DeviceResult> addDevice(
    Map<String, dynamic> data, {
    String? deviceNo,
    required String webhook,
    required String token,
  }) {
    final argv = <String, dynamic>{
      'type': 'add',
      'data': data,
    };
    if (deviceNo != null && deviceNo.isNotEmpty) {
      argv['device_no'] = deviceNo;
    }
    return _invoke(argv, webhook: webhook, token: token);
  }

  /// 按设备编号删除对应表格行。
  static Future<DeviceResult> deleteDevice(
    String deviceNo, {
    required String webhook,
    required String token,
  }) {
    return _invoke(
      <String, dynamic>{'type': 'delete', 'device_no': deviceNo},
      webhook: webhook,
      token: token,
    );
  }

  /// 获取远端表格的一页设备行，并返回分页状态。
  static Future<DeviceListResult> listDevices({
    required String webhook,
    required String token,
    int start = 0,
    int limit = 100,
    bool includeEmpty = false,
  }) async {
    return DeviceListResult.fromJson(
      await _invokeRaw(
        <String, dynamic>{
          'type': 'list',
          'start': start,
          'limit': limit,
          'includeEmpty': includeEmpty,
        },
        webhook: webhook,
        token: token,
      ),
    );
  }
}

/// 脚本返回结果的类型化封装
class DeviceResult {
  final Map<String, dynamic> raw; // 原始返回 Map，避免丢失字段

  final bool success;
  final String? type;
  final String? deviceNo;
  final int? row;
  final Map<String, dynamic>? data;
  final String? message;
  final int? deletedRow;
  final Map<String, dynamic>? deletedData;

  DeviceResult._(this.raw)
      : success = raw['success'] == true,
        type = raw['type'] as String?,
        deviceNo = raw['device_no'] as String?,
        row = raw['row'] as int?,
        data = raw['data'] as Map<String, dynamic>?,
        message = raw['message'] as String?,
        deletedRow = raw['deletedRow'] as int?,
        deletedData = raw['deletedData'] as Map<String, dynamic>?;

  factory DeviceResult.fromJson(Map<String, dynamic> json) =>
      DeviceResult._(json);

  /// 失败原因（success=false 时通常有值）
  String? get errorMessage => success ? null : (message ?? '未知错误');
}

/// 脚本 list 接口返回的完整设备行集合。
class DeviceListResult {
  final Map<String, dynamic> raw;
  final bool success;
  final String? type;
  final String? message;
  final int? total;
  final int? start;
  final int? limit;
  final int? nextStart;
  final bool hasMore;
  final List<Map<String, dynamic>> rows;

  DeviceListResult._(this.raw)
      : success = raw['success'] == true,
        type = raw['type'] as String?,
        message = raw['message'] as String?,
        total = (raw['total'] as num?)?.toInt(),
        start = (raw['start'] as num?)?.toInt(),
        limit = (raw['limit'] as num?)?.toInt(),
        nextStart = (raw['nextStart'] as num?)?.toInt(),
        hasMore = raw['hasMore'] == true,
        rows = <Map<String, dynamic>>[
          for (final row in raw['rows'] as List<dynamic>? ?? const [])
            if (row is Map) Map<String, dynamic>.from(row),
        ];

  /// 从脚本业务结果构建列表模型。
  factory DeviceListResult.fromJson(Map<String, dynamic> json) =>
      DeviceListResult._(json);

  /// 返回业务失败时可直接展示的消息。
  String? get errorMessage => success ? null : (message ?? '未知错误');
}

/// 脚本/HTTP 层异常（区别于业务失败：业务失败在 result.success=false）
class DeviceApiException implements Exception {
  final String message;
  DeviceApiException(this.message);

  @override
  String toString() => 'DeviceApiException: $message';
}
