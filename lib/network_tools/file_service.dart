import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:excel_app/log/app_log.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

const _networkChannel = MethodChannel('com.example.excel_app/network');

class FileServer {
  final int _port;
  final Directory _saveDir;
  HttpServer? _server;
  Uint8List? _pendingExport;
  String? _pendingExportName;
  String _pendingExportContentType = 'text/csv; charset=utf-8';

  /// 文件接收完成后的回调，参数为保存目录
  void Function(Directory saveDir)? onFilesReceived;

  /// 当保存目录已有文件时，询问是否允许用本次上传文件替换旧文件。
  Future<bool> Function(List<String> filenames)? onReplaceExistingFiles;

  /// 电脑成功下载已排队导出文件后的回调。
  void Function()? onExportDownloaded;

  FileServer({int port = 8080, required Directory saveDir})
      : _port = port,
        _saveDir = saveDir;

  String? get pendingExportFilename => _pendingExportName;

  /// 返回系统实际分配的监听端口。
  int? get boundPort => _server?.port;

  /// 排队一个等待电脑浏览器下载的文件及其 MIME 类型。
  void queueExport(
    Uint8List bytes,
    String filename, {
    String contentType = 'text/csv; charset=utf-8',
  }) {
    _pendingExport = Uint8List.fromList(bytes);
    _pendingExportName = filename;
    _pendingExportContentType = contentType;
  }

  /// 绑定服务端口；返回时表示端口已经成功监听。
  Future<void> init() async {
    _saveDir.createSync(recursive: true);
    try {
      final server = await HttpServer.bind(InternetAddress.anyIPv4, _port);
      _server = server;
      debugPrint('文件服务已启动: http://${await getLocalIp()}:${server.port}');
      _listen(server);
    } catch (error, stackTrace) {
      AppLog.error('[FileServer][init] failed port=$_port', error, stackTrace);
      rethrow;
    }
  }

  /// 在端口绑定成功后持续处理浏览器请求。
  void _listen(HttpServer server) {
    server.listen((request) async {
      try {
        if (request.method == 'GET') {
          if (request.uri.path == '/export') {
            await _handleExport(request);
          } else {
            _handleGet(request);
          }
        } else if (request.method == 'POST' && request.uri.path == '/upload') {
          await _handleUpload(request);
        } else {
          request.response.statusCode = HttpStatus.notFound;
          await request.response.close();
        }
      } catch (error, stackTrace) {
        AppLog.error('[FileServer][request] failed path=${request.uri.path}',
            error, stackTrace);
        try {
          request.response.statusCode = HttpStatus.internalServerError;
          await request.response.close();
        } catch (_) {}
      }
    }, onError: (Object error, StackTrace stackTrace) {
      AppLog.error(
          '[FileServer][listen] failed port=$_port', error, stackTrace);
    });
  }

  void _handleGet(HttpRequest request) {
    request.response.statusCode = HttpStatus.ok;
    request.response.headers.set('Content-Type', 'text/html; charset=utf-8');
    request.response.write('''
<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>设备管理</title>
<style>
:root {
  color-scheme: light;
  --primary: #126782;
  --primary-dark: #0c4e64;
  --ink: #17313b;
  --muted: #65777f;
  --line: #d9e4e8;
  --surface: #ffffff;
  --page: #f4f7f9;
}
* { box-sizing: border-box; }
body {
  margin: 0;
  min-height: 100vh;
  background: var(--page);
  color: var(--ink);
  font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", "Microsoft YaHei", sans-serif;
}
.page {
  width: min(720px, calc(100% - 32px));
  margin: 0 auto;
  padding: 48px 0 64px;
}
.brand { margin-bottom: 28px; }
.eyebrow {
  margin: 0 0 8px;
  color: var(--primary);
  font-size: 13px;
  font-weight: 700;
  letter-spacing: .08em;
}
h1 { margin: 0; font-size: clamp(28px, 5vw, 42px); line-height: 1.15; }
.subtitle { margin: 12px 0 0; color: var(--muted); font-size: 16px; }
.panel {
  padding: 28px;
  background: var(--surface);
  border: 1px solid var(--line);
  border-radius: 16px;
  box-shadow: 0 12px 30px rgba(23, 49, 59, .06);
}
.dropzone {
  display: block;
  padding: 32px 24px;
  border: 1px dashed #9ab5bf;
  border-radius: 12px;
  background: #f8fbfc;
  text-align: center;
  cursor: pointer;
  transition: border-color .2s, background .2s;
}
.dropzone:hover, .dropzone:focus-within { border-color: var(--primary); background: #f0f8fa; }
.drop-icon { color: var(--primary); font-size: 32px; line-height: 1; }
.drop-title { margin: 12px 0 6px; font-weight: 700; }
.drop-hint { margin: 0; color: var(--muted); font-size: 14px; }
#fileInput { position: absolute; width: 1px; height: 1px; opacity: 0; }
#fileNames { margin: 14px 0 0; color: var(--muted); font-size: 14px; }
.actions { display: flex; flex-wrap: wrap; gap: 12px; margin-top: 22px; }
button {
  min-height: 44px;
  padding: 0 18px;
  border: 1px solid transparent;
  border-radius: 10px;
  font: inherit;
  font-weight: 700;
  cursor: pointer;
}
.primary { background: var(--primary); color: #fff; }
.primary:hover { background: var(--primary-dark); }
.secondary { border-color: var(--line); background: #fff; color: var(--ink); }
.secondary:hover { border-color: var(--primary); color: var(--primary); }
#status {
  margin: 20px 0 0;
  padding: 12px 14px;
  border-left: 3px solid var(--primary);
  background: #f3f8fa;
  color: var(--muted);
  line-height: 1.5;
}
@media (max-width: 520px) {
  .page { padding-top: 28px; }
  .panel { padding: 20px; }
  .actions button { width: 100%; }
}
</style>
</head>
<body>
<main class="page">
  <header class="brand">
    <p class="eyebrow">设备管理 · 文件服务</p>
    <h1>手机与电脑文件传输</h1>
    <p class="subtitle">电脑上传表格到手机，手机发送文件到电脑时会自动下载。</p>
  </header>
  <section class="panel">
    <form id="uploadForm" enctype="multipart/form-data">
      <label class="dropzone" for="fileInput">
        <div class="drop-icon">↥</div>
        <div class="drop-title">选择要发送的表格文件</div>
        <p class="drop-hint">每次只能选择一个文件</p>
        <input id="fileInput" type="file" name="file" required>
      </label>
      <p id="fileNames">尚未选择文件</p>
      <div class="actions">
        <button class="primary" type="submit">发送到手机</button>
      </div>
      <p class="transfer-note">手机发送的文件会自动下载到电脑浏览器的默认下载目录，无需额外操作。</p>
    </form>
    <p id="status" role="status">等待操作</p>
  </section>
</main>
<script>
const form = document.getElementById('uploadForm');
const status = document.getElementById('status');
const fileInput = document.getElementById('fileInput');
const fileNames = document.getElementById('fileNames');
fileInput.addEventListener('change', function() {
  const file = fileInput.files && fileInput.files[0];
  fileNames.textContent = file ? file.name : '尚未选择文件';
});
form.addEventListener('submit', async function(event) {
  event.preventDefault();
  status.textContent = '文件发送中，请稍候...';
  try {
    const response = await fetch('/upload', {
      method: 'POST',
      body: new FormData(form)
    });
    status.textContent = await response.text();
  } catch (error) {
    status.textContent = '发送失败，请检查手机连接。';
  }
});

async function pollExport() {
  try {
    const response = await fetch('/export', {cache: 'no-store'});
    if (response.status !== 200) return;
    const blob = await response.blob();
    const disposition = response.headers.get('Content-Disposition') || '';
    const match = disposition.match(/filename[*]=UTF-8''([^;]+)/);
    const filename = match ? decodeURIComponent(match[1]) : 'edited.xls';
    const link = document.createElement('a');
    link.href = URL.createObjectURL(blob);
    link.download = filename;
    link.click();
    setTimeout(function() { URL.revokeObjectURL(link.href); }, 1000);
    status.textContent = '已接收并下载: ' + filename;
  } catch (error) {
    // 电脑暂时无法连接时，下一轮继续检查。
  }
}
setInterval(pollExport, 1000);
</script>
</body></html>
    ''');
    request.response.close();
  }

  /// 返回手机保存后的文件，电脑页面轮询到后自动下载。
  Future<void> _handleExport(HttpRequest request) async {
    final bytes = _pendingExport;
    final filename = _pendingExportName;
    final contentType = _pendingExportContentType;
    if (bytes == null || filename == null) {
      request.response.statusCode = HttpStatus.noContent;
      await request.response.close();
      return;
    }

    _pendingExport = null;
    _pendingExportName = null;
    _pendingExportContentType = 'text/csv; charset=utf-8';
    request.response.statusCode = HttpStatus.ok;
    request.response.headers.set(
      'Content-Type',
      contentType,
    );
    request.response.headers.set(
      'Content-Disposition',
      "attachment; filename*=UTF-8''${Uri.encodeComponent(filename)}",
    );
    request.response.headers.contentLength = bytes.length;
    request.response.add(bytes);
    await request.response.close();
    onExportDownloaded?.call();
  }

  Future<void> _handleUpload(HttpRequest request) async {
    final contentType = request.headers.contentType;
    if (contentType == null || contentType.mimeType != 'multipart/form-data') {
      request.response.statusCode = HttpStatus.badRequest;
      request.response.write('非 multipart 请求');
      await request.response.close();
      return;
    }

    final boundary = contentType.parameters['boundary'];
    if (boundary == null) {
      request.response.statusCode = HttpStatus.badRequest;
      request.response.write('缺少 boundary');
      await request.response.close();
      return;
    }

    try {
      final bodyBytes = await _collectBytes(request);
      final parts = _parseMultipart(bodyBytes, boundary);
      final filenames = [
        for (final part in parts)
          if (part.filename != null && part.filename!.isNotEmpty)
            part.filename!,
      ];
      if (filenames.isEmpty) {
        request.response.statusCode = HttpStatus.badRequest;
        request.response.write('没有收到文件');
        await request.response.close();
        return;
      }

      final hasExistingFiles = _saveDir.existsSync() &&
          _saveDir.listSync().any(
                (entity) => entity is File && !entity.path.endsWith('.tmp'),
              );
      if (hasExistingFiles) {
        final shouldReplace =
            await onReplaceExistingFiles?.call(filenames) ?? true;
        if (!shouldReplace) {
          request.response.statusCode = HttpStatus.conflict;
          request.response.write('已取消替换本地文件');
          await request.response.close();
          return;
        }
        await _clearOldFiles();
      }

      final savedFiles = <String>[];
      for (final part in parts) {
        if (part.filename != null && part.filename!.isNotEmpty) {
          final file = File('${_saveDir.path}/${part.filename}');
          await file.writeAsBytes(part.data);
          savedFiles.add(part.filename!);
        }
      }

      // ✅ 目标1：通知UI有新文件到达
      if (savedFiles.isNotEmpty) {
        onFilesReceived?.call(_saveDir);
      }

      request.response.statusCode = HttpStatus.ok;
      request.response.headers.set('Content-Type', 'text/plain; charset=utf-8');
      request.response.write('已发送: ${savedFiles.join(", ")}');
    } catch (e) {
      request.response.statusCode = HttpStatus.internalServerError;
      request.response.write('上传失败: $e');
    }

    await request.response.close();
  }

  /// 清空保存目录中的旧文件
  Future<void> _clearOldFiles() async {
    if (_saveDir.existsSync()) {
      for (final entity in _saveDir.listSync()) {
        if (entity is File) {
          await entity.delete();
        }
      }
    }
  }

  Future<Uint8List> _collectBytes(HttpRequest request) async {
    final builder = BytesBuilder(copy: false);
    await for (final chunk in request) {
      builder.add(chunk);
    }
    return builder.takeBytes();
  }

  List<_MultipartPart> _parseMultipart(Uint8List body, String boundary) {
    final parts = <_MultipartPart>[];
    final boundaryBytes = utf8.encode('--$boundary');
    final bodyStr = utf8.decode(body, allowMalformed: true);

    final sections = bodyStr.split('--$boundary');

    for (final section in sections) {
      if (section.trim().isEmpty || section.trim() == '--') continue;

      final headerEndIndex = section.indexOf('\r\n\r\n');
      if (headerEndIndex == -1) continue;

      final headerStr = section.substring(0, headerEndIndex);
      final bodyContent = section.substring(headerEndIndex + 4);

      final trimmedBody = bodyContent.endsWith('\r\n')
          ? bodyContent.substring(0, bodyContent.length - 2)
          : bodyContent;

      String? filename;
      final filenameMatch = RegExp(r'filename="([^"]*)"').firstMatch(headerStr);
      if (filenameMatch != null) {
        filename = filenameMatch.group(1);
      }

      if (filename != null) {
        final headerEndByteIndex = _indexOfPattern(
            body,
            utf8.encode('\r\n\r\n'),
            _indexOfSection(body, boundaryBytes, sections.indexOf(section)));

        if (headerEndByteIndex != -1) {
          final dataStart = headerEndByteIndex + 4;
          final sectionEndBytes =
              _findSectionEnd(body, boundaryBytes, dataStart);
          final dataEnd =
              sectionEndBytes != -1 ? sectionEndBytes - 2 : body.length;

          if (dataEnd > dataStart) {
            parts.add(_MultipartPart(
              filename: filename,
              data: body.sublist(dataStart, dataEnd),
            ));
            continue;
          }
        }
      }

      parts.add(_MultipartPart(
        filename: filename,
        data: utf8.encode(trimmedBody),
      ));
    }

    return parts;
  }

  int _indexOfSection(
      Uint8List body, List<int> boundaryBytes, int sectionIndex) {
    if (sectionIndex <= 0) return 0;
    int pos = 0;
    for (int i = 0; i < sectionIndex; i++) {
      final found = _indexOfPattern(body, boundaryBytes, pos);
      if (found == -1) return -1;
      pos = found + boundaryBytes.length;
    }
    return pos;
  }

  int _findSectionEnd(Uint8List body, List<int> boundaryBytes, int from) {
    return _indexOfPattern(body, boundaryBytes, from);
  }

  int _indexOfPattern(Uint8List body, List<int> pattern, int start) {
    outer:
    for (int i = start; i <= body.length - pattern.length; i++) {
      for (int j = 0; j < pattern.length; j++) {
        if (body[i + j] != pattern[j]) continue outer;
      }
      return i;
    }
    return -1;
  }

  void release() async {
    await _server?.close(force: true);
    _server = null;
  }
}

class _MultipartPart {
  final String? filename;
  final List<int> data;
  _MultipartPart({this.filename, required this.data});
}

/// 获取本机局域网 IP
Future<String?> getLocalIp() async {
  if (Platform.isAndroid) {
    try {
      final ip = await _networkChannel.invokeMethod<String>('getWifiIp');
      if (ip != null && ip.isNotEmpty) return ip;
    } catch (_) {
      // Android native lookup is unavailable; do not scan all Android interfaces.
    }
    return null;
  }

  try {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLinkLocal: false,
    );
    for (final iface in interfaces) {
      for (final addr in iface.addresses) {
        if (!addr.isLoopback && !addr.isLinkLocal) {
          return addr.address;
        }
      }
    }
  } catch (_) {
    // 没有可用网络信息时仍允许服务继续启动。
  }
  return null;
}

/// 获取当前 Wi-Fi 名称；系统限制或非 Android 平台返回 null。
Future<String?> getWifiSsid() async {
  if (!Platform.isAndroid) return null;
  try {
    final ssid = await _networkChannel.invokeMethod<String>('getWifiSsid');
    if (ssid == null || ssid.isEmpty || ssid == '<unknown ssid>') return null;
    return ssid;
  } catch (_) {
    return null;
  }
}
