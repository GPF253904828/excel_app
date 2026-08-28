import 'dart:convert';
import 'package:http/http.dart' as http;

/// 设备表脚本接口封装（对应 WPS 端 JS 脚本的 query/modify/add/delete 四类操作）
class DeviceApi {
  DeviceApi._(); // 工具类，禁止实例化

  /// 统一调用脚本接口并解析脚本返回结果。
  static Future<DeviceResult> _invoke(
    Map<String, dynamic> argv, {
    required String webhook,
    required String token,
  }) async {
    final resp = await http.post(
      Uri.parse(webhook),
      headers: {
        'AirScript-Token': token,
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'Context': {'argv': argv},
      }),
    );

    if (resp.statusCode != 200) {
      throw DeviceApiException('HTTP ${resp.statusCode}: ${resp.body}');
    }

    final json =
        jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;

    // 脚本执行失败（语法错误、异常中断等）
    if ((json['status'] ?? '') != 'finished' || (json['error'] ?? '') != '') {
      throw DeviceApiException('脚本执行异常: ${json['error']}');
    }

    // 脚本 return 的对象在 data.result
    final data = json['data'] as Map<String, dynamic>? ?? {};
    final result = (data['result'] as Map<String, dynamic>?) ?? {};
    return DeviceResult.fromJson(result);
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

/// 脚本/HTTP 层异常（区别于业务失败：业务失败在 result.success=false）
class DeviceApiException implements Exception {
  final String message;
  DeviceApiException(this.message);

  @override
  String toString() => 'DeviceApiException: $message';
}
