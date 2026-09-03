import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:excel_app/utils/app_log.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

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
  AppLog.info('[Diagnostics][snapshot] $encoded');
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
