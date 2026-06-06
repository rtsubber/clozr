import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

// Conditional import for web-only window access
import 'base_path_stub.dart'
    if (dart.library.html) 'base_path_web.dart';

/// Authentication service — handles login/register/JWT via backend
/// Replaces client-side API key storage (H1 fix)
class AuthService {
  static const _keyToken = 'clozr_jwt_token';
  static const _keyAccountId = 'clozr_account_id';
  static const _keyBrandName = 'clozr_brand_name';
  static const _keyEmail = 'clozr_email';

  /// Base path for subpath deployment (e.g. "/clozr").
  ///
  /// DETECTED AT RUNTIME from the browser's window.location.pathname.
  /// This is critical because String.fromEnvironment bakes values into
  /// the compiled JS at build time, making it impossible for a single
  /// build to work at both localhost:8510/ (root) and /clozr/ (subpath).
  ///
  /// Detection logic:
  ///   - If window.location.pathname starts with "/clozr" → basePath = "/clozr"
  ///   - Otherwise → basePath = "" (root deployment)
  ///
  /// This way, the SAME build works at:
  ///   - http://localhost:8510/           → basePath = "" → API: /api/*
  ///   - https://domain/clozr/           → basePath = "/clozr" → API: /clozr/api/*
  static String _basePath = '';
  static bool _basePathInitialized = false;

  /// Configured base path from build-time dart-define.
  /// Falls back to runtime detection on web.
  static const String _configuredBasePath = String.fromEnvironment(
    'CLOZR_BASE_PATH',
    defaultValue: '',
  );

  /// Get the base path, initializing from config or browser if needed
  static String get basePath {
    if (!_basePathInitialized) {
      // Use build-time config if set, otherwise detect at runtime
      _basePath = _configuredBasePath.isNotEmpty ? _configuredBasePath : detectBasePath();
      _basePathInitialized = true;
    }
    return _basePath;
  }

  String _baseUrl;
  String? _token;
  String? _accountId;
  String? _brandName;

  AuthService({String baseUrl = ''}) : _baseUrl = baseUrl;

  /// Full API URL prefix for constructing request paths.
  ///
  /// In subpath deployment: basePath="/clozr", baseUrl="" → apiUrl="/clozr"
  ///   → Uri.parse('$apiUrl/api/auth/login') = '/clozr/api/auth/login' ✅
  ///
  /// In root deployment:  basePath="", baseUrl="" → apiUrl=""
  ///   → Uri.parse('$apiUrl/api/auth/login') = '/api/auth/login' ✅
  ///
  /// IMPORTANT: Always use `apiUrl` instead of `baseUrl` when constructing
  /// API request URLs. `baseUrl` is the raw server origin (for dev mode),
  /// while `apiUrl` includes the subpath prefix.
  String get apiUrl => _baseUrl.isNotEmpty ? _baseUrl : basePath;

  String get baseUrl => _baseUrl;
  String? get token => _token;
  String? get accountId => _accountId;
  String? get brandName => _brandName;
  bool get isAuthenticated => _token != null && _token!.isNotEmpty;

  /// Auto-detect backend URL from browser location or use provided URL.
  ///
  /// Returns empty string for same-origin deployment (the normal case).
  /// The basePath is detected separately and handles subpath routing.
  ///
  /// For cross-origin development, you can pass --dart-define=CLOZR_BACKEND_URL=http://localhost:8510
  static String detectBackendUrl() {
    const configured = String.fromEnvironment('CLOZR_BACKEND_URL');
    if (configured.isNotEmpty) return configured;
    // Same-origin: empty string means relative URLs resolve against current origin
    return '';
  }

  /// Load saved auth state from SharedPreferences
  Future<void> loadFromStorage() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString(_keyToken);
    _accountId = prefs.getString(_keyAccountId);
    _brandName = prefs.getString(_keyBrandName);
  }

  /// Save auth state to SharedPreferences
  Future<void> _saveToStorage() async {
    final prefs = await SharedPreferences.getInstance();
    if (_token != null) {
      await prefs.setString(_keyToken, _token!);
    } else {
      await prefs.remove(_keyToken);
    }
    if (_accountId != null) {
      await prefs.setString(_keyAccountId, _accountId!);
    } else {
      await prefs.remove(_keyAccountId);
    }
    if (_brandName != null) {
      await prefs.setString(_keyBrandName, _brandName!);
    } else {
      await prefs.remove(_keyBrandName);
    }
  }

  /// Register a new account
  Future<bool> register({
    required String email,
    required String password,
    String name = '',
    String company = '',
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$apiUrl/api/auth/register'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': email,
          'password': password,
          'name': name,
          'company': company,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        _token = data['token'] as String?;
        _accountId = data['account_id'] as String?;
        _brandName = data['brand_name'] as String? ?? company;
        await _saveToStorage();
        return true;
      }

      if (response.statusCode == 409) {
        // Email already exists — try login instead
        return login(email: email, password: password);
      }

      return false;
    } catch (_) {
      return false;
    }
  }

  /// Login with existing account
  Future<bool> login({
    required String email,
    required String password,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$apiUrl/api/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': email,
          'password': password,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        _token = data['token'] as String?;
        _accountId = data['account_id'] as String?;
        _brandName = data['brand_name'] as String? ?? 'The Clozr';

        // Save email for convenience
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_keyEmail, email);
        await _saveToStorage();
        return true;
      }

      return false;
    } catch (_) {
      return false;
    }
  }

  /// Get account info from backend
  Future<Map<String, dynamic>?> getAccount() async {
    if (_token == null) return null;
    try {
      final response = await http.get(
        Uri.parse('$apiUrl/api/account'),
        headers: authHeaders,
      );
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
      // Token expired or invalid
      if (response.statusCode == 401) {
        await logout();
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Update account branding
  Future<bool> updateAccount({
    String? name,
    String? company,
    String? brandName,
    String? brandColor,
    String? accentColor,
  }) async {
    if (_token == null) return false;
    try {
      final body = <String, dynamic>{};
      if (name != null) body['name'] = name;
      if (company != null) body['company'] = company;
      if (brandName != null) body['brand_name'] = brandName;
      if (brandColor != null) body['brand_color'] = brandColor;
      if (accentColor != null) body['accent_color'] = accentColor;

      final response = await http.put(
        Uri.parse('$apiUrl/api/account'),
        headers: authHeaders,
        body: jsonEncode(body),
      );

      if (response.statusCode == 200) {
        if (brandName != null) {
          _brandName = brandName;
          await _saveToStorage();
        }
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Logout — clear stored auth
  Future<void> logout() async {
    _token = null;
    _accountId = null;
    _brandName = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyToken);
    await prefs.remove(_keyAccountId);
    await prefs.remove(_keyBrandName);
  }

  /// Get saved email for login form prefill
  Future<String> getSavedEmail() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyEmail) ?? '';
  }

  /// Auth headers for API calls
  Map<String, String> get authHeaders => {
    'Authorization': 'Bearer $_token',
    'Content-Type': 'application/json',
  };
}