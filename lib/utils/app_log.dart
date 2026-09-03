import 'dart:io';

import 'package:logger/logger.dart';
import 'package:path_provider/path_provider.dart';

/// 提供应用级诊断日志的初始化、写入和读取能力。
class AppLog {
  AppLog._();

  static Logger? _logger;
  static File? _file;

  /// 初始化文件日志；测试可传入临时目录，生产环境使用应用支持目录。
  static Future<void> initialize({Directory? directory}) async {
    final targetDirectory = directory ?? await getApplicationSupportDirectory();
    await targetDirectory.create(recursive: true);
    _file = File('${targetDirectory.path}/app.log');
    await _file!.create();
    _logger = Logger(
      filter: ProductionFilter(),
      printer: PrettyPrinter(methodCount: 0, errorMethodCount: 0),
      output: _FileLogOutput(_file!),
    );
    info('[AppLog][initialized] path=${_file!.path}');
  }

  /// 写入普通诊断信息；日志尚未初始化时忽略，避免影响主流程。
  static void info(String message) => _logger?.i(message);

  /// 写入错误和堆栈信息；日志尚未初始化时忽略，避免影响主流程。
  static void error(String message, [Object? error, StackTrace? stackTrace]) {
    _logger?.e(message, error: error, stackTrace: stackTrace);
  }

  /// 返回当前日志文件路径。
  static Future<String?> get filePath async => _file?.path;

  /// 读取最近日志内容，文件不存在时返回空文本。
  static Future<String> read() async {
    final file = _file;
    if (file == null || !await file.exists()) return '';
    return file.readAsString();
  }

  /// 读取日志二进制内容，用于上传或导出。
  static Future<List<int>> readBytes() async {
    final file = _file;
    if (file == null || !await file.exists()) return <int>[];
    return file.readAsBytes();
  }
}

/// 将 logger 输出同步追加到单一文件，保证诊断页打开时内容已可读取。
class _FileLogOutput extends LogOutput {
  final File file;

  _FileLogOutput(this.file);

  @override
  void output(OutputEvent event) {
    file.writeAsStringSync('${event.lines.join('\n')}\n',
        mode: FileMode.append);
  }
}
