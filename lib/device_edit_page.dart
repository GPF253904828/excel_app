import 'package:flutter/material.dart';

/// 提供设备数据行的新增、编辑和保存操作。
class DeviceEditPage extends StatefulWidget {
  final List<String> headers;
  final List<String> initialRow;
  final bool isNew;
  final Future<void> Function(List<String> row) onSave;

  /// Creates a device row editor with the provided headers and initial values.
  const DeviceEditPage({
    super.key,
    required this.headers,
    required this.initialRow,
    required this.isNew,
    required this.onSave,
  });

  /// Creates the mutable state for this editor page.
  @override
  State<DeviceEditPage> createState() => _DeviceEditPageState();
}

class _DeviceEditPageState extends State<DeviceEditPage> {
  late final List<TextEditingController> _controllers;
  late bool _deviceCodeEditable;
  bool _saving = false;
  String? _errorMessage;

  /// Creates one input controller for each header and fills missing cells.
  @override
  void initState() {
    super.initState();
    _controllers = List<TextEditingController>.generate(
      widget.headers.length,
      (index) => TextEditingController(
        text: index < widget.initialRow.length ? widget.initialRow[index] : '',
      ),
    );
    _deviceCodeEditable = widget.isNew;
  }

  /// Shows the required confirmation before enabling an existing device code.
  Future<void> _confirmDeviceCodeEdit() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('确认修改设备编码'),
        content: const Text('改编码可能影响行匹配'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('确认修改'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;
    setState(() => _deviceCodeEditable = true);
  }

  /// Removes focus from the current input when another page area is tapped.
  void _dismissKeyboard() {
    FocusManager.instance.primaryFocus?.unfocus();
  }

  /// Collects the row, saves it, and returns it only after a successful save.
  Future<void> _save() async {
    if (_saving) return;

    setState(() {
      _saving = true;
      _errorMessage = null;
    });
    final row = _controllers.map((controller) => controller.text).toList();

    try {
      await widget.onSave(row);
      if (!mounted) return;
      Navigator.pop(context, row);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _errorMessage = '保存失败: $error';
      });
    }
  }

  /// Releases every input controller owned by this page.
  @override
  void dispose() {
    for (final controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  /// Builds the input associated with one header.
  Widget _buildField(int index) {
    final header = widget.headers[index];
    final field = TextField(
      key: Key('field-$header'),
      controller: _controllers[index],
      enabled: !_saving && (header != '设备编号' || _deviceCodeEditable),
      onTapOutside: (_) => _dismissKeyboard(),
      decoration: const InputDecoration(
        isDense: true,
        hintText: '请输入内容',
      ),
    );

    final content = header != '设备编号' || widget.isNew
        ? field
        : Row(
            children: [
              Expanded(child: field),
              IconButton(
                tooltip: '修改设备编码',
                onPressed: _saving || _deviceCodeEditable
                    ? null
                    : _confirmDeviceCodeEdit,
                icon: const Icon(Icons.edit_outlined),
              ),
            ],
          );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 92,
          child: Text(
            '$header：',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        Expanded(child: content),
      ],
    );
  }

  /// Builds the page fields, save action, and save error state.
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _dismissKeyboard,
      child: Scaffold(
        appBar: AppBar(
          title: GestureDetector(
            onTap: _dismissKeyboard,
            child: const Text('编辑设备'),
          ),
        ),
        body: SafeArea(
          child: ListView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            children: [
              for (var index = 0; index < widget.headers.length; index++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _buildField(index),
                ),
              if (_errorMessage != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(_errorMessage!),
                ),
              FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: const Icon(Icons.save_outlined),
                label: const Text('保存'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
