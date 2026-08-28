import 'package:shared_preferences/shared_preferences.dart';

/// 在线脚本接口所需的连接配置。
class OnlineApiConfig {
  final String url;
  final String token;

  const OnlineApiConfig({required this.url, required this.token});
}

/// 保存和读取在线脚本接口配置。
class OnlineConfigStore {
  static const String _urlKey = 'online_api_url';
  static const String _tokenKey = 'online_api_token';

  const OnlineConfigStore();

  /// 读取完整配置；任一配置为空时返回 null。
  Future<OnlineApiConfig?> load() async {
    final preferences = await SharedPreferences.getInstance();
    final url = preferences.getString(_urlKey)?.trim() ?? '';
    final token = preferences.getString(_tokenKey)?.trim() ?? '';
    if (url.isEmpty || token.isEmpty) return null;
    return OnlineApiConfig(url: url, token: token);
  }

  /// 持久化 URL 和 Token，并返回已保存的配置。
  Future<OnlineApiConfig> save({
    required String url,
    required String token,
  }) async {
    final normalizedUrl = url.trim();
    final normalizedToken = token.trim();
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_urlKey, normalizedUrl);
    await preferences.setString(_tokenKey, normalizedToken);
    return OnlineApiConfig(url: normalizedUrl, token: normalizedToken);
  }
}
