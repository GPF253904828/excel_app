import 'dart:typed_data';

const int _freeSector = 0xFFFFFFFF;
const int _endOfChain = 0xFFFFFFFE;
const int _noStream = 0xFFFFFFFF;

/// 表格数据的简单模型，第一行是表头，其余内容是数据行。
class XlsTable {
  final List<String> headers;
  final List<List<String>> rows;

  XlsTable({required this.headers, required this.rows});
}

/// 读取 Excel 97-2003 BIFF8 文件中的首张工作表。
class XlsReader {
  /// 将 XLS 二进制内容解析为可展示的表格数据。
  XlsTable read(Uint8List bytes) {
    final workbook = _CompoundFile(bytes).stream('Workbook');
    if (workbook == null) {
      throw const FormatException('XLS 文件中没有 Workbook 工作簿');
    }

    final parser = _BiffParser(workbook);
    parser.readGlobals();
    return parser.readFirstSheet();
  }
}

class _CompoundFile {
  final Uint8List _bytes;
  late final int _sectorSize;
  late final List<int> _fat;
  late final Uint8List _directory;

  _CompoundFile(this._bytes) {
    if (_bytes.length < 512 || _u32(0) != 0xE011CFD0) {
      throw const FormatException('不是有效的 XLS 文件');
    }
    _sectorSize = 1 << _u16(0x1E);
    final difat = <int>[];
    for (var i = 0; i < 109; i++) {
      final sector = _u32(0x4C + i * 4);
      if (sector != _freeSector) difat.add(sector);
    }

    final fatSectors = <int>[];
    for (final sector in difat) {
      final data = _sector(sector);
      for (var i = 0; i < _sectorSize; i += 4) {
        fatSectors.add(_readU32(data, i));
      }
    }
    _fat = fatSectors;
    _directory = _readChain(_u32(0x30));
  }

  Uint8List? stream(String expectedName) {
    for (var offset = 0; offset + 128 <= _directory.length; offset += 128) {
      final nameLength = _readU16(_directory, offset + 64);
      if (nameLength < 2) continue;
      final nameBytes = _directory.sublist(offset, offset + nameLength - 2);
      final name = String.fromCharCodes(_decodeUtf16(nameBytes));
      if (name != expectedName) continue;

      final start = _readU32(_directory, offset + 116);
      final size = _readU64(_directory, offset + 120);
      return _readChain(start, size: size);
    }
    return null;
  }

  Uint8List _readChain(int start, {int? size}) {
    if (start == _endOfChain || start == _noStream) return Uint8List(0);
    final result = BytesBuilder(copy: false);
    final visited = <int>{};
    var sector = start;
    while (sector != _endOfChain && sector != _freeSector) {
      if (!visited.add(sector) || sector >= _fat.length) break;
      result.add(_sector(sector));
      sector = _fat[sector];
    }
    final bytes = result.takeBytes();
    return size == null || size >= bytes.length
        ? bytes
        : Uint8List.sublistView(bytes, 0, size);
  }

  Uint8List _sector(int index) {
    final start = 512 + index * _sectorSize;
    if (start < 0 || start + _sectorSize > _bytes.length) {
      throw const FormatException('XLS 文件的扇区数据不完整');
    }
    return Uint8List.sublistView(_bytes, start, start + _sectorSize);
  }

  int _u16(int offset) => _readU16(_bytes, offset);
  int _u32(int offset) => _readU32(_bytes, offset);
}

class _BiffParser {
  final Uint8List _bytes;
  final List<String> _sharedStrings = [];
  int? _firstSheetOffset;

  _BiffParser(this._bytes);

  void readGlobals() {
    _forEachRecord((sid, data, offset) {
      if (sid == 0x0085 && _firstSheetOffset == null) {
        _firstSheetOffset = _readU32(data, 0);
      } else if (sid == 0x00FC) {
        _readSharedStrings(data);
      }
    });
  }

  XlsTable readFirstSheet() {
    final start = _firstSheetOffset;
    if (start == null) throw const FormatException('XLS 文件没有工作表');

    final values = <int, Map<int, dynamic>>{};
    var maxColumn = -1;
    var maxRow = -1;
    _forEachRecord((sid, data, offset) {
      if (offset < start) return;
      if (sid == 0x000A) return;
      final cell = _cell(sid, data);
      if (cell == null) return;
      final row = cell.row;
      final column = cell.column;
      values.putIfAbsent(row, () => <int, dynamic>{})[column] = cell.value;
      if (row > maxRow) maxRow = row;
      if (column > maxColumn) maxColumn = column;
    });

    if (maxRow < 0 || maxColumn < 0) return XlsTable(headers: [], rows: []);
    var headerRow = 0;
    while (headerRow <= maxRow &&
        !values.containsKey(headerRow) &&
        headerRow < maxRow) {
      headerRow++;
    }
    final headers = List<String>.generate(
        maxColumn + 1, (column) => _display(values[headerRow]?[column]));
    final rows = <List<String>>[];
    for (var row = headerRow + 1; row <= maxRow; row++) {
      final source = values[row] ?? const <int, dynamic>{};
      if (source.isEmpty) continue;
      rows.add(List<String>.generate(maxColumn + 1, (column) {
        final value = source[column];
        if (value is num && _isDateHeader(headers[column])) {
          return _excelDate(value.toDouble());
        }
        return _display(value);
      }));
    }
    return XlsTable(headers: headers, rows: rows);
  }

  void _forEachRecord(
      void Function(int sid, Uint8List data, int offset) callback) {
    var offset = 0;
    while (offset + 4 <= _bytes.length) {
      final sid = _readU16(_bytes, offset);
      final length = _readU16(_bytes, offset + 2);
      final end = offset + 4 + length;
      if (end > _bytes.length) break;
      callback(sid, Uint8List.sublistView(_bytes, offset + 4, end), offset);
      offset = end;
    }
  }

  void _readSharedStrings(Uint8List data) {
    if (data.length < 8) return;
    var offset = 8;
    while (offset < data.length) {
      final parsed = _readUnicodeString(data, offset);
      if (parsed == null) break;
      _sharedStrings.add(parsed.text);
      offset = parsed.nextOffset;
    }
  }

  _Cell? _cell(int sid, Uint8List data) {
    if (data.length < 8) return null;
    final row = _readU16(data, 0);
    final column = _readU16(data, 2);
    switch (sid) {
      case 0x00FD:
        final index = _readU32(data, 6);
        return _Cell(row, column,
            index < _sharedStrings.length ? _sharedStrings[index] : '');
      case 0x0203:
      case 0x0006:
        if (data.length < 14) return null;
        return _Cell(row, column, _readDouble(data, 6));
      case 0x027E:
        return _Cell(row, column, _decodeRk(_readU32(data, 6)));
      case 0x0204:
        final parsed = _readUnicodeString(data, 6);
        return parsed == null ? null : _Cell(row, column, parsed.text);
      case 0x0205:
        return _Cell(row, column, data.length > 8 && data[8] != 0);
      case 0x00BD:
        return null;
    }
    return null;
  }

  dynamic _decodeRk(int value) {
    if ((value & 2) != 0) return (value >> 2).toDouble();
    final bits = (value & 0xFFFFFFFC) << 32;
    final data = ByteData(8)..setUint64(0, bits, Endian.little);
    return data.getFloat64(0, Endian.little);
  }

  String _display(dynamic value) {
    if (value == null) return '';
    if (value is double && value == value.roundToDouble()) {
      return value.toInt().toString();
    }
    return '$value';
  }

  bool _isDateHeader(String header) =>
      header.contains('日期') || header.contains('有效期') || header.contains('时间');

  String _excelDate(double serial) {
    final date = DateTime.utc(1899, 12, 30).add(
        Duration(milliseconds: (serial * Duration.millisecondsPerDay).round()));
    return '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }
}

class _Cell {
  final int row;
  final int column;
  final dynamic value;

  _Cell(this.row, this.column, this.value);
}

class _ParsedString {
  final String text;
  final int nextOffset;

  _ParsedString(this.text, this.nextOffset);
}

_ParsedString? _readUnicodeString(Uint8List data, int offset) {
  if (offset + 3 > data.length) return null;
  final length = _readU16(data, offset);
  final options = data[offset + 2];
  var cursor = offset + 3;
  var richCount = 0;
  var extensionLength = 0;
  if ((options & 0x08) != 0) {
    if (cursor + 2 > data.length) return null;
    richCount = _readU16(data, cursor);
    cursor += 2;
  }
  if ((options & 0x04) != 0) {
    if (cursor + 4 > data.length) return null;
    extensionLength = _readU32(data, cursor);
    cursor += 4;
  }
  final byteLength = (options & 0x01) == 0 ? length : length * 2;
  if (cursor + byteLength > data.length) return null;
  final textBytes = data.sublist(cursor, cursor + byteLength);
  final text = (options & 0x01) == 0
      ? String.fromCharCodes(textBytes)
      : String.fromCharCodes(_decodeUtf16(textBytes));
  cursor += byteLength + richCount * 4 + extensionLength;
  return _ParsedString(text, cursor);
}

List<int> _decodeUtf16(List<int> bytes) {
  final units = <int>[];
  for (var i = 0; i + 1 < bytes.length; i += 2) {
    units.add(bytes[i] | (bytes[i + 1] << 8));
  }
  return units;
}

int _readU16(List<int> bytes, int offset) =>
    bytes[offset] | (bytes[offset + 1] << 8);

int _readU32(List<int> bytes, int offset) =>
    _readU16(bytes, offset) | (_readU16(bytes, offset + 2) << 16);

int _readU64(List<int> bytes, int offset) =>
    _readU32(bytes, offset) | (_readU32(bytes, offset + 4) << 32);

double _readDouble(List<int> bytes, int offset) {
  final data = ByteData.sublistView(Uint8List.fromList(bytes));
  return data.getFloat64(offset, Endian.little);
}
