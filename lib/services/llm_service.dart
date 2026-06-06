import 'dart:convert';
import 'package:http/http.dart' as http;
import 'auth_service.dart';

/// LLM Service — routes through backend proxy (H1/A1 fix)
/// No API keys stored client-side. Server handles provider selection.
class LLMService {
  final AuthService _auth;

  LLMService(this._auth);

  /// Summarize a meeting transcript via backend proxy
  Future<String> summarizeMeeting(String transcript) async {
    if (!_auth.isAuthenticated) {
      throw Exception('Not authenticated. Please log in.');
    }

    final response = await http.post(
      Uri.parse('${_auth.apiUrl}/api/llm'),
      headers: _auth.authHeaders,
      body: jsonEncode({
        'transcript': transcript,
        'task': 'summarize',
      }),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final result = data['result'];
      if (result is Map<String, dynamic>) {
        return result['summary'] ?? jsonEncode(result);
      }
      return result.toString();
    }

    if (response.statusCode == 401) {
      throw Exception('Session expired. Please log in again.');
    }

    throw Exception('Summarization failed: ${response.statusCode}');
  }

  /// Detect workflows from transcript via backend proxy
  Future<List<Map<String, dynamic>>> detectWorkflows(String transcript) async {
    if (!_auth.isAuthenticated) {
      throw Exception('Not authenticated. Please log in.');
    }

    final response = await http.post(
      Uri.parse('${_auth.apiUrl}/api/llm'),
      headers: _auth.authHeaders,
      body: jsonEncode({
        'transcript': transcript,
        'task': 'detect_workflows',
      }),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final result = data['result'];
      if (result is Map<String, dynamic> && result.containsKey('detected_workflows')) {
        return (result['detected_workflows'] as List).cast<Map<String, dynamic>>();
      }
      return [];
    }

    if (response.statusCode == 401) {
      throw Exception('Session expired. Please log in again.');
    }

    throw Exception('Workflow detection failed: ${response.statusCode}');
  }

  /// Generate a proposal from meeting data via backend proxy
  Future<Map<String, dynamic>> generateProposal({
    required String transcript,
    String? businessName,
  }) async {
    if (!_auth.isAuthenticated) {
      throw Exception('Not authenticated. Please log in.');
    }

    final response = await http.post(
      Uri.parse('${_auth.apiUrl}/api/llm'),
      headers: _auth.authHeaders,
      body: jsonEncode({
        'transcript': transcript,
        'task': 'generate_proposal',
      }),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final result = data['result'];
      if (result is Map<String, dynamic>) {
        return result;
      }
      return {'raw_content': result.toString()};
    }

    if (response.statusCode == 401) {
      throw Exception('Session expired. Please log in again.');
    }

    throw Exception('Proposal generation failed: ${response.statusCode}');
  }

  /// Generate a follow-up email from meeting data via backend proxy
  Future<Map<String, dynamic>> generateFollowUp({
    required String transcript,
  }) async {
    if (!_auth.isAuthenticated) {
      throw Exception('Not authenticated. Please log in.');
    }

    final response = await http.post(
      Uri.parse('${_auth.apiUrl}/api/llm'),
      headers: _auth.authHeaders,
      body: jsonEncode({
        'transcript': transcript,
        'task': 'generate_followup',
      }),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data; // Returns {result: {...}, meeting_data: {...}, stages: "2"}
    }

    if (response.statusCode == 401) {
      throw Exception('Session expired. Please log in again.');
    }

    throw Exception('Follow-up email generation failed: ${response.statusCode}');
  }
}