import 'dart:convert';
import 'package:http/http.dart' as http;
import 'auth_service.dart';

/// Local-Eye Business Verification Service — now via backend proxy (A1 fix)
/// No API keys client-side; server handles Local-Eye token acquisition
class LocaleyeService {
  final AuthService _auth;

  LocaleyeService(this._auth);

  /// Verify a business by phone number — routed through backend
  Future<Map<String, dynamic>> verifyBusiness({
    required String phone,
    String? businessName,
  }) async {
    if (!_auth.isAuthenticated) {
      throw Exception('Not authenticated. Please log in.');
    }

    final response = await http.post(
      Uri.parse('${_auth.apiUrl}/api/localeye/verify'),
      headers: _auth.authHeaders,
      body: jsonEncode({
        'phone': phone,
        if (businessName != null) 'business_name': businessName,
      }),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }

    if (response.statusCode == 401) {
      throw Exception('Session expired. Please log in again.');
    }

    if (response.statusCode == 503) {
      throw Exception('Local-Eye verification is not configured on the server.');
    }

    throw Exception('Business verification failed: ${response.statusCode}');
  }
}