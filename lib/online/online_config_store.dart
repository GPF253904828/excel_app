import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// 在线脚本接口的一条可选连接配置。
class OnlineApiConfig {
  static const String builtInId = 'builtin';
  static const String builtInUrl =
      'https://www.kdocs.cn/api/v3/ide/file/cjQJmvEX03n2/script/V2-7LfFuITpzY7ymzPf8OfNy7/sync_task';
  static const String _builtInToken = '4UZv073cHuHyHkLy8WbLaU';

  final String id;
  final String url;
  final String token;
  final bool isBuiltIn;

  const OnlineApiConfig({
    required this.id,
    required this.url,
    required this.token,
    this.isBuiltIn = false,
  });

  /// 返回应用内置且不可编辑的默认连接配置。
  static const OnlineApiConfig builtIn = OnlineApiConfig(
    id: builtInId,
    url: builtInUrl,
    token: _builtInToken,
    isBuiltIn: true,
  );

  /// 用局部字段覆盖当前配置，供编辑自定义项时保持稳定 ID。
  OnlineApiConfig copyWith({String? url, String? token}) => OnlineApiConfig(
        id: id,
        url: url ?? this.url,
        token: token ?? this.token,
        isBuiltIn: isBuiltIn,
      );

  /// 将自定义配置转换为持久化 JSON 数据。
  Map<String, String> toJson() => <String, String>{
        'id': id,
        'url': url,
        'token': token,
      };

  /// 从持久化 JSON 数据恢复自定义配置。
  factory OnlineApiConfig.fromJson(Map<String, dynamic> json) =>
      OnlineApiConfig(
        id: json['id']?.toString() ?? '',
        url: json['url']?.toString().trim() ?? '',
        token: json['token']?.toString().trim() ?? '',
      );
}

/// 保存、迁移和选择在线脚本的连接配置。
class OnlineConfigStore {
  static const String _legacyUrlKey = 'online_api_url';
  static const String _legacyTokenKey = 'online_api_token';
  static const String _configsKey = 'online_api_configs';
  static const String _selectedIdKey = 'online_api_selected_id';

  const OnlineConfigStore();

  /// 返回内置配置和所有已保存的自定义配置，并在首次读取时迁移旧配置。
  Future<List<OnlineApiConfig>> loadAll() async {
    final preferences = await SharedPreferences.getInstance();
    final stored = preferences.getString(_configsKey);
    final customConfigs = stored == null
        ? await _migrateLegacyConfig(preferences)
        : _decodeConfigs(stored);
    return <OnlineApiConfig>[OnlineApiConfig.builtIn, ...customConfigs];
  }

  /// 返回当前选中的配置；没有显式选择时默认使用内置配置。
  Future<OnlineApiConfig?> load() async {
    final preferences = await SharedPreferences.getInstance();
    final configs = await loadAll();
    final selectedId = preferences.getString(_selectedIdKey);
    for (final config in configs) {
      if (config.id == selectedId) return config;
    }
    return OnlineApiConfig.builtIn;
  }

  /// 新增一条自定义配置并返回规范化后的数据。
  Future<OnlineApiConfig> create({
    required String url,
    required String token,
  }) async {
    final config = _customConfig(url: url, token: token);
    final preferences = await SharedPreferences.getInstance();
    final customs = _customConfigs(await loadAll());
    customs.add(config);
    await _writeCustomConfigs(preferences, customs);
    return config;
  }

  /// 修改已有的自定义配置；内置配置始终不可修改。
  Future<OnlineApiConfig> update(OnlineApiConfig config) async {
    if (config.isBuiltIn || config.id == OnlineApiConfig.builtInId) {
      throw StateError('内置配置不可修改');
    }
    final updated = _customConfig(
      id: config.id,
      url: config.url,
      token: config.token,
    );
    final preferences = await SharedPreferences.getInstance();
    final customs = _customConfigs(await loadAll());
    final index = customs.indexWhere((item) => item.id == updated.id);
    if (index < 0) throw StateError('配置不存在');
    customs[index] = updated;
    await _writeCustomConfigs(preferences, customs);
    return updated;
  }

  /// 删除自定义配置；删除当前选择时自动回退到内置配置。
  Future<void> delete(String id) async {
    if (id == OnlineApiConfig.builtInId) {
      throw StateError('内置配置不可删除');
    }
    final preferences = await SharedPreferences.getInstance();
    final customs = _customConfigs(await loadAll());
    if (!customs.any((config) => config.id == id)) {
      throw StateError('配置不存在');
    }
    customs.removeWhere((config) => config.id == id);
    await _writeCustomConfigs(preferences, customs);
    if (preferences.getString(_selectedIdKey) == id) {
      await preferences.setString(_selectedIdKey, OnlineApiConfig.builtInId);
    }
  }

  /// 持久化当前使用的配置 ID。
  Future<void> select(String id) async {
    final configs = await loadAll();
    if (!configs.any((config) => config.id == id)) {
      throw StateError('配置不存在');
    }
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_selectedIdKey, id);
  }

  /// 兼容旧调用方：保存为自定义配置并立即设为当前配置。
  Future<OnlineApiConfig> save({
    required String url,
    required String token,
  }) async {
    final config = await create(url: url, token: token);
    await select(config.id);
    return config;
  }

  /// 从旧版单配置键迁移自定义项，并保留旧用户的活动选择。
  Future<List<OnlineApiConfig>> _migrateLegacyConfig(
    SharedPreferences preferences,
  ) async {
    final url = preferences.getString(_legacyUrlKey)?.trim() ?? '';
    final token = preferences.getString(_legacyTokenKey)?.trim() ?? '';
    final customs = <OnlineApiConfig>[];
    if (_isValid(url, token) &&
        (url != OnlineApiConfig.builtInUrl ||
            token != OnlineApiConfig.builtIn.token)) {
      customs.add(_customConfig(id: 'legacy', url: url, token: token));
    }
    await _writeCustomConfigs(preferences, customs);
    if (customs.isNotEmpty && preferences.getString(_selectedIdKey) == null) {
      await preferences.setString(_selectedIdKey, customs.single.id);
    }
    await preferences.remove(_legacyUrlKey);
    await preferences.remove(_legacyTokenKey);
    return customs;
  }

  /// 解析持久化数据，忽略损坏或不完整的配置项。
  List<OnlineApiConfig> _decodeConfigs(String stored) {
    try {
      final values = jsonDecode(stored) as List<dynamic>;
      return <OnlineApiConfig>[
        for (final value in values)
          if (value is Map)
            OnlineApiConfig.fromJson(Map<String, dynamic>.from(value)),
      ]
          .where(
            (config) =>
                _isValid(config.url, config.token) && config.id.isNotEmpty,
          )
          .toList();
    } catch (_) {
      return <OnlineApiConfig>[];
    }
  }

  /// 过滤出可持久化的自定义项，避免内置项被写入偏好设置。
  List<OnlineApiConfig> _customConfigs(List<OnlineApiConfig> configs) =>
      configs.where((config) => !config.isBuiltIn).toList();

  /// 写入完整的自定义配置列表。
  Future<void> _writeCustomConfigs(
    SharedPreferences preferences,
    List<OnlineApiConfig> configs,
  ) =>
      preferences.setString(
        _configsKey,
        jsonEncode(configs.map((config) => config.toJson()).toList()),
      );

  /// 规范化并校验自定义配置。
  OnlineApiConfig _customConfig({
    String? id,
    required String url,
    required String token,
  }) {
    final normalizedUrl = url.trim();
    final normalizedToken = token.trim();
    if (!_isValid(normalizedUrl, normalizedToken)) {
      throw ArgumentError('请输入有效 URL 和 Token');
    }
    return OnlineApiConfig(
      id: id ?? 'custom-${DateTime.now().microsecondsSinceEpoch}',
      url: normalizedUrl,
      token: normalizedToken,
    );
  }

  /// 判断 URL 和 Token 是否满足调用接口的最小要求。
  static bool _isValid(String url, String token) =>
      Uri.tryParse(url)?.hasScheme == true && token.trim().isNotEmpty;
}
