import 'package:flutter/foundation.dart' show kIsWeb;
import 'auth_service.dart';

/// App configuration — backend URL only, no client-side API keys (H1 fix)
/// All provider calls route through the authenticated backend proxy
class AppConfig {
  /// Backend URL — for cross-origin development only.
  /// In normal deployment (same-origin), leave empty and the app
  /// uses relative API paths with runtime-detected basePath.
  ///
  /// For cross-origin dev: --dart-define=CLOZR_BACKEND_URL=http://localhost:8510
  /// For same-origin (normal): leave unset (empty)
  static const String backendUrl = String.fromEnvironment(
    'CLOZR_BACKEND_URL',
    defaultValue: '',  // Empty = same-origin, runtime basePath detection
  );

  /// Whether we're running in demo/offline mode
  static bool get isDemo => backendUrl.isEmpty || backendUrl == 'demo';

  /// App version
  static const String version = '0.2.1';

  /// Navigate to a route, adding basePath prefix on web.
  /// Use this instead of raw '/login', '/meeting' etc. in GoRouter navigation.
  static String route(String path) {
    if (kIsWeb && AuthService.basePath.isNotEmpty) {
      // Ensure path starts with /
      if (!path.startsWith('/')) path = '/$path';
      return '${AuthService.basePath}$path';
    }
    return path;
  }
}