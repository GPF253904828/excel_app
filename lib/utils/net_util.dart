import 'dart:convert';
import 'package:http/http.dart' as http;

/// 设备表脚本接口封装（对应 WPS 端 JS 脚本的 query/modify/add/delete 四类操作）
class DeviceApi {
  DeviceApi._(); // 工具类，禁止实例化

  static String _webhook =
      'https://www.kdocs.cn/api/v3/ide/file/cjQJmvEX03n2/script/V2-7LfFuITpzY7ymzPf8OfNy7/sync_task';

  /// 在脚本编辑器【脚本令牌】创建的 APIToken 'YOUR_AIRSCRIPT_TOKEN';
  static String _token = '2JoT05mhFYtnsRKgPuAiq7';

  /// 初始化（也可直接给 static 字段赋值）
  static void configureWebhook({required String webhook}) {
    _webhook = webhook;
  }

  /// 初始化（也可直接给 static 字段赋值）
  static void configureToken({required String token}) {
    _token = token;
  }

  // ------------------------------------------------------------------
  // 核心调用：统一处理 HTTP 请求、脚本级错误、结果解析
  // ------------------------------------------------------------------
  static Future<DeviceResult> _invoke(Map<String, dynamic> argv) async {
    final resp = await http.post(
      Uri.parse(_webhook),
      headers: {
        'AirScript-Token': _token,
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

  // 1) 查询：按设备编号返回所在行数据
  static Future<DeviceResult> queryDevice(String deviceNo) {
    return _invoke({
      'type': 'query',
      'device_no': deviceNo,
    });
  }

  // 2) 修改：回写 data 中出现的列，返回更新后的整行
  //    data 示例：{'状态': '维修中', '负责人': '张三'}
  static Future<DeviceResult> modifyDevice(
    String deviceNo,
    Map<String, dynamic> data,
  ) {
    return _invoke({
      'type': 'modify',
      'device_no': deviceNo,
      'data': data,
    });
  }

  // 3) 新增：追加一行到表格末尾
  //    data 需包含设备编号（或通过 deviceNo 参数单独传入）
  static Future<DeviceResult> addDevice(
    Map<String, dynamic> data, {
    String? deviceNo,
  }) {
    final argv = <String, dynamic>{
      'type': 'add',
      'data': data,
    };
    if (deviceNo != null && deviceNo.isNotEmpty) {
      argv['device_no'] = deviceNo;
    }
    return _invoke(argv);
  }

  // 4) 删除：按设备编号删除所在行
  static Future<DeviceResult> deleteDevice(String deviceNo) {
    return _invoke({
      'type': 'delete',
      'device_no': deviceNo,
    });
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
