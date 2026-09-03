import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:excel_app/log/app_log.dart';
import 'package:excel_app/network_tools/file_service.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// 收集当前 Wi-Fi/局域网接口的简要信息，供页面辅助展示。
Future<String> collectNetworkInfo() async {
  const unavailable = 'Wi-Fi 网卡: 未获取\nIPv4: 未获取\nIPv6: 未获取\nWi-Fi 名称: 未获取';
  try {
    final interfaces = await NetworkInterface.list(
      includeLinkLocal: true,
    );
    NetworkInterface? selected;
    for (final network in interfaces) {
      final name = network.name.toLowerCase();
      if (name == 'wlan0' || name.contains('wifi') || name.startsWith('en')) {
        selected = network;
        break;
      }
    }
    selected ??= interfaces.firstWhere(
      (network) => network.addresses.any(
        (address) => !address.isLoopback && !address.isLinkLocal,
      ),
      orElse: () => throw StateError('没有可用的 Wi-Fi 网卡'),
    );

    final ipv4 = selected.addresses
        .where((address) => address.type == InternetAddressType.IPv4)
        .map((address) => address.address)
        .join(', ');
    final ipv6 = selected.addresses
        .where((address) => address.type == InternetAddressType.IPv6)
        .map((address) => address.address)
        .join(', ');
    final ssid = await getWifiSsid();
    return 'Wi-Fi 网卡: ${selected.name}\n'
        'IPv4: ${ipv4.isEmpty ? '未获取' : ipv4}\n'
        'IPv6: ${ipv6.isEmpty ? '未获取' : ipv6}\n'
        'Wi-Fi 名称: ${ssid ?? '未获取'}';
  } catch (error, stackTrace) {
    AppLog.error(
        '[Diagnostics][network] display information failed', error, stackTrace);
    return unavailable;
  }
}

/// 收集设备、网络接口和文件服务状态，输出可直接交给技术支持分析的 JSON。
Future<String> collectDiagnostics({
  String? serverStatus,
  int? serverPort,
  String? serverLocalIp,
}) async {
  final interfaces = <Map<String, dynamic>>[];
  try {
    for (final network in await NetworkInterface.list(
      includeLoopback: true,
      includeLinkLocal: true,
    )) {
      interfaces.add(<String, dynamic>{
        'name': network.name,
        'addresses': [
          for (final address in network.addresses)
            <String, dynamic>{
              'address': address.address,
              'type': address.type.name,
              'isLoopback': address.isLoopback,
              'isLinkLocal': address.isLinkLocal,
            },
        ],
      });
    }
  } catch (error, stackTrace) {
    AppLog.error('[Diagnostics][network] interface enumeration failed', error,
        stackTrace);
  }

  final report = <String, dynamic>{
    'capturedAt': DateTime.now().toIso8601String(),
    'operatingSystem': Platform.operatingSystem,
    'operatingSystemVersion': Platform.operatingSystemVersion,
    'localHostname': Platform.localHostname,
    'dartVersion': Platform.version,
    'networkInterfaces': interfaces,
    'server': <String, dynamic>{
      'status': serverStatus ?? 'unknown',
      'port': serverPort,
      'localIp': serverLocalIp,
      'url': serverLocalIp == null || serverPort == null
          ? null
          : 'http://$serverLocalIp:$serverPort',
    },
  };
  final encoded = const JsonEncoder.withIndent('  ').convert(report);
  AppLog.info('[Diagnostics][network] $encoded');
  return encoded;
}

/// 将日志和诊断快照压缩为带时间戳的 ZIP 文件。
Future<File> createDiagnosticsZip(
  File logFile, {
  required Directory directory,
  String? diagnostics,
}) async {
  await directory.create(recursive: true);
  final now = DateTime.now();
  final timestamp = '${now.year.toString().padLeft(4, '0')}'
      '${now.month.toString().padLeft(2, '0')}'
      '${now.day.toString().padLeft(2, '0')}_'
      '${now.hour.toString().padLeft(2, '0')}'
      '${now.minute.toString().padLeft(2, '0')}'
      '${now.second.toString().padLeft(2, '0')}';
  final zipFile = File('${directory.path}/diagnostic_$timestamp.zip');
  final archive = Archive()
    ..addFile(ArchiveFile(
        'app.log',
        logFile.existsSync() ? logFile.lengthSync() : 0,
        logFile.existsSync() ? logFile.readAsBytesSync() : <int>[]));
  if (diagnostics != null && diagnostics.isNotEmpty) {
    final bytes = utf8.encode(diagnostics);
    archive.addFile(ArchiveFile('diagnostics.json', bytes.length, bytes));
  }
  final encoded = ZipEncoder().encode(archive);
  await zipFile.writeAsBytes(encoded!);
  return zipFile;
}

/// 创建诊断 ZIP 并调起系统分享面板，支持微信、QQ 等已安装应用。
Future<File> shareDiagnostics({
  String? serverStatus,
  int? serverPort,
  String? serverLocalIp,
}) async {
  final logPath = await AppLog.filePath;
  final logFile = File(logPath ?? '');
  final appDirectory = await getTemporaryDirectory();
  final diagnostics = await collectDiagnostics(
    serverStatus: serverStatus,
    serverPort: serverPort,
    serverLocalIp: serverLocalIp,
  );
  final zip = await createDiagnosticsZip(
    logFile,
    directory: appDirectory,
    diagnostics: diagnostics,
  );
  await Share.shareXFiles(
    <XFile>[XFile(zip.path, mimeType: 'application/zip')],
    subject: '设备管理诊断日志',
    text: '设备管理诊断日志，请协助分析局域网通信问题。',
  );
  return zip;
}
