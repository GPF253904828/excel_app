import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:network_info_plus/network_info_plus.dart';

class FileServer {
  final int _port;
  final Directory _saveDir;
  HttpServer? _server;
  Uint8List? _pendingExport;
  String? _pendingExportName;

  /// 文件接收完成后的回调，参数为保存目录
  void Function(Directory saveDir)? onFilesReceived;

  FileServer({int port = 8080, required Directory saveDir})
      : _port = port,
        _saveDir = saveDir;

  /// 排队一个等待电脑浏览器下载的文件。
  void queueExport(Uint8List bytes, String filename) {
    _pendingExport = Uint8List.fromList(bytes);
    _pendingExportName = filename;
  }

  Future<void> init() async {
    _saveDir.createSync(recursive: true);

    final server = await HttpServer.bind(InternetAddress.anyIPv4, _port);
    _server = server;
    print('文件服务已启动: http://${await getLocalIp()}:$_port');

    await for (final HttpRequest request in server) {
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
    }
  }

  void _handleGet(HttpRequest request) {
    request.response.statusCode = HttpStatus.ok;
    request.response.headers.set('Content-Type', 'text/html; charset=utf-8');
    request.response.write('''
<!DOCTYPE html>
<html><head><meta charset="utf-8"><title>文件传输</title></head>
<body>
<h2>发送文件到手机</h2>
<form id="uploadForm" enctype="multipart/form-data">
  <input type="file" name="file" multiple required>
  <button type="submit">上传</button>
</form>
<button id="folderButton" type="button">选择保存文件夹</button>
<p id="status">等待操作</p>
<script>
const form = document.getElementById('uploadForm');
const status = document.getElementById('status');
const folderButton = document.getElementById('folderButton');
let exportDirectory = null;
folderButton.addEventListener('click', async function() {
  if (!window.showDirectoryPicker) {
    status.textContent = '当前浏览器不支持选择文件夹，将使用默认下载目录';
    return;
  }
  try {
    exportDirectory = await window.showDirectoryPicker({mode: 'readwrite'});
    status.textContent = '已选择保存文件夹';
  } catch (error) {
    status.textContent = '未选择保存文件夹';
  }
});

form.addEventListener('submit', async function(event) {
  event.preventDefault();
  status.textContent = '发送中...';
  try {
    const response = await fetch('/upload', {
      method: 'POST',
      body: new FormData(form)
    });
    status.textContent = await response.text();
  } catch (error) {
    status.textContent = '发送失败';
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
    if (exportDirectory) {
      const fileHandle = await exportDirectory.getFileHandle(filename, {create: true});
      const writable = await fileHandle.createWritable();
      await writable.write(blob);
      await writable.close();
      status.textContent = '已接收并保存: ' + filename;
    } else {
      const link = document.createElement('a');
      link.href = URL.createObjectURL(blob);
      link.download = filename;
      link.click();
      setTimeout(function() { URL.revokeObjectURL(link.href); }, 1000);
      status.textContent = '已接收并下载: ' + filename;
    }
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
    if (bytes == null || filename == null) {
      request.response.statusCode = HttpStatus.noContent;
      await request.response.close();
      return;
    }

    _pendingExport = null;
    _pendingExportName = null;
    request.response.statusCode = HttpStatus.ok;
    request.response.headers.set(
      'Content-Type',
      'text/csv; charset=utf-8',
    );
    request.response.headers.set(
      'Content-Disposition',
      "attachment; filename*=UTF-8''${Uri.encodeComponent(filename)}",
    );
    request.response.headers.contentLength = bytes.length;
    request.response.add(bytes);
    await request.response.close();
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

    final savedFiles = <String>[];

    try {
      // ✅ 目标2：上传新文件前，先清空旧文件
      await _clearOldFiles();

      final bodyBytes = await _collectBytes(request);
      final parts = _parseMultipart(bodyBytes, boundary);

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
  try {
    final wifiIp = await NetworkInfo().getWifiIP();
    if (wifiIp != null && wifiIp.isNotEmpty) return wifiIp;
  } catch (_) {
    // 插件在部分 release 设备上不可用时，继续使用 Dart 接口枚举。
  }

  try {
    for (final iface
        in await NetworkInterface.list(type: InternetAddressType.IPv4)) {
      for (final addr in iface.addresses) {
        if (!addr.isLoopback && !addr.isLinkLocal) {
          return addr.address;
        }
      }
    }
  } on SocketException {
    // 没有网络接口时仍允许服务继续启动，页面会显示未获取到 IP。
  }
  return null;
}
