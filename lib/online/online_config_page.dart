import 'package:excel_app/online/online_config_store.dart';
import 'package:flutter/material.dart';

/// 管理在线脚本接口的内置和自定义连接配置。
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
  List<OnlineApiConfig> _configs = const <OnlineApiConfig>[];
  String? _selectedId;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// 读取配置列表和当前选中项。
  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final configs = await widget.store.loadAll();
      final selected = await widget.store.load();
      if (!mounted) return;
      setState(() {
        _configs = configs;
        _selectedId = selected?.id;
      });
    } catch (error) {
      if (mounted) setState(() => _error = '读取配置失败: $error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// 更新页面中的临时选择，确认前不写入偏好设置。
  void _select(String? id) {
    if (id != null) setState(() => _selectedId = id);
  }

  /// 持久化当前选择，并把它返回给在线页面。
  Future<void> _confirmSelection() async {
    final id = _selectedId;
    if (id == null || _loading) return;
    OnlineApiConfig? config;
    for (final item in _configs) {
      if (item.id == id) {
        config = item;
        break;
      }
    }
    if (config == null) return;
    setState(() => _loading = true);
    try {
      await widget.store.select(config.id);
      if (mounted) Navigator.pop(context, config);
    } catch (error) {
      if (mounted) setState(() => _error = '选择配置失败: $error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// 在对话框中新增或编辑一条自定义配置。
  Future<void> _openEditor([OnlineApiConfig? config]) async {
    if (config?.isBuiltIn == true) return;
    final urlController = TextEditingController(text: config?.url ?? '');
    final tokenController = TextEditingController(text: config?.token ?? '');
    String? error;
    var saving = false;
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text(config == null ? '新增配置' : '编辑配置'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                key: const Key('online-config-url'),
                controller: urlController,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(labelText: 'URL'),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('online-config-token'),
                controller: tokenController,
                decoration: const InputDecoration(labelText: 'Token'),
              ),
              if (error != null) ...[
                const SizedBox(height: 12),
                Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(dialogContext),
              child: const Text('取消'),
            ),
            FilledButton(
              key: const Key('online-config-save'),
              onPressed: saving
                  ? null
                  : () async {
                      setDialogState(() {
                        saving = true;
                        error = null;
                      });
                      try {
                        if (config == null) {
                          await widget.store.create(
                            url: urlController.text,
                            token: tokenController.text,
                          );
                        } else {
                          await widget.store.update(config.copyWith(
                            url: urlController.text,
                            token: tokenController.text,
                          ));
                        }
                        if (mounted) Navigator.pop(dialogContext, true);
                      } catch (exception) {
                        setDialogState(() {
                          saving = false;
                          error = exception.toString();
                        });
                      }
                    },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
    urlController.dispose();
    tokenController.dispose();
    if (saved == true && mounted) await _load();
  }

  /// 确认后删除一条自定义配置。
  Future<void> _delete(OnlineApiConfig config) async {
    if (config.isBuiltIn || _loading) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除配置'),
        content: Text('确定删除 ${config.url} 吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.store.delete(config.id);
      if (mounted) await _load();
    } catch (error) {
      if (mounted) setState(() => _error = '删除配置失败: $error');
    }
  }

  /// 构建一项可选择的配置，并限制内置项的操作入口。
  Widget _configTile(OnlineApiConfig config) => Card(
        margin: const EdgeInsets.only(bottom: 8),
        child: ListTile(
          key: Key('online-config-select-${config.id}'),
          onTap: _loading ? null : () => _select(config.id),
          leading: Radio<String>(
            value: config.id,
            groupValue: _selectedId,
            onChanged: _loading ? null : _select,
          ),
          title: Row(
            children: [
              Expanded(child: SelectableText(config.url)),
              if (config.isBuiltIn) const Chip(label: Text('内置')),
            ],
          ),
          subtitle: SelectableText('Token: ${config.token}'),
          trailing: config.isBuiltIn
              ? null
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      key: Key('online-config-edit-${config.id}'),
                      tooltip: '编辑配置',
                      onPressed: _loading ? null : () => _openEditor(config),
                      icon: const Icon(Icons.edit_outlined),
                    ),
                    IconButton(
                      key: Key('online-config-delete-${config.id}'),
                      tooltip: '删除配置',
                      onPressed: _loading ? null : () => _delete(config),
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ],
                ),
        ),
      );

  /// 构建配置列表、选择确认和新增入口。
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('接口配置'),
        actions: [
          IconButton(
            key: const Key('online-config-add'),
            tooltip: '新增配置',
            onPressed: _loading ? null : () => _openEditor(),
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: _loading && _configs.isEmpty
                  ? const Center(child: CircularProgressIndicator())
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                      children: [
                        for (final config in _configs) _configTile(config),
                        if (_error != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              _error!,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                          ),
                      ],
                    ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  key: const Key('online-config-confirm'),
                  onPressed: _loading ? null : _confirmSelection,
                  icon: const Icon(Icons.check),
                  label: const Text('确认使用'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
