import 'package:excel_app/online/online_config_store.dart';
import 'package:flutter/material.dart';

/// 编辑并保存在线脚本 API 的 URL 与 Token。
class OnlineConfigPage extends StatefulWidget {
  final OnlineConfigStore store;

  const OnlineConfigPage({
    super.key,
    this.store = const OnlineConfigStore(),
  });

  @override
  State<OnlineConfigPage> createState() => _OnlineConfigPageState();
}

class _OnlineConfigPageState extends State<OnlineConfigPage> {
  final TextEditingController _urlController = TextEditingController();
  final TextEditingController _tokenController = TextEditingController();
  OnlineApiConfig? _savedConfig;
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _urlController.dispose();
    _tokenController.dispose();
    super.dispose();
  }

  /// 读取上次保存的配置并填充输入框。
  Future<void> _load() async {
    final config = await widget.store.load();
    if (!mounted || config == null) return;
    setState(() {
      _savedConfig = config;
      _urlController.text = config.url;
      _tokenController.text = config.token;
    });
  }

  /// 校验后保存配置，并将结果返回给调用页。
  Future<void> _save() async {
    final url = _urlController.text.trim();
    final token = _tokenController.text.trim();
    if (Uri.tryParse(url)?.hasScheme != true || token.isEmpty) {
      setState(() => _error = '请输入有效 URL 和 Token');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final config = await widget.store.save(url: url, token: token);
      if (!mounted) return;
      setState(() => _savedConfig = config);
      if (Navigator.canPop(context)) Navigator.pop(context, config);
    } catch (error) {
      if (mounted) setState(() => _error = '保存失败: $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// 构建接口配置的编辑页面。
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('接口配置')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (_savedConfig != null) ...[
            Text('当前文件: ${_savedConfig!.fileName}'),
            const SizedBox(height: 20),
          ],
          TextField(
            key: const Key('online-config-url'),
            controller: _urlController,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              labelText: 'URL',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            key: const Key('online-config-token'),
            controller: _tokenController,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Token',
              border: OutlineInputBorder(),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!),
          ],
          const SizedBox(height: 24),
          FilledButton(
            key: const Key('online-config-save'),
            onPressed: _saving ? null : _save,
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }
}
