import 'package:shared_preferences/shared_preferences.dart';

/// Centralized API key management
/// Stores keys in SharedPreferences (works on web via localStorage)
class ApiKeys {
  static const _keyGroq = 'groq_api_key';
  static const _keyOpenRouter = 'openrouter_api_key';
  static const _keyLocaleye = 'localeye_api_key';
  static const _keyPorcupine = 'porcupine_access_key';

  String groqApiKey;
  String openRouterApiKey;
  String localeyeApiKey;
  String porcupineAccessKey;

  ApiKeys({
    this.groqApiKey = '',
    this.openRouterApiKey = '',
    this.localeyeApiKey = '',
    this.porcupineAccessKey = '',
  });

  bool get hasGroq => groqApiKey.isNotEmpty;
  bool get hasOpenRouter => openRouterApiKey.isNotEmpty;
  bool get hasLocaleye => localeyeApiKey.isNotEmpty;
  bool get hasPorcupine => porcupineAccessKey.isNotEmpty;
  bool get hasAnyKey => hasGroq || hasOpenRouter;

  static Future<ApiKeys> load() async {
    final prefs = await SharedPreferences.getInstance();
    return ApiKeys(
      groqApiKey: prefs.getString(_keyGroq) ?? '',
      openRouterApiKey: prefs.getString(_keyOpenRouter) ?? '',
      localeyeApiKey: prefs.getString(_keyLocaleye) ?? '',
      porcupineAccessKey: prefs.getString(_keyPorcupine) ?? '',
    );
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyGroq, groqApiKey);
    await prefs.setString(_keyOpenRouter, openRouterApiKey);
    await prefs.setString(_keyLocaleye, localeyeApiKey);
    await prefs.setString(_keyPorcupine, porcupineAccessKey);
  }
}