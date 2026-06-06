import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/meeting.dart';
import 'auth_service.dart';

/// Meeting Storage — now via backend API instead of localStorage (A2/A3 fix)
/// All data server-side with proper auth and multi-tenant isolation
class MeetingStorage {
  /// Save a meeting to the backend
  static Future<Meeting> save(Meeting meeting, AuthService auth) async {
    if (!auth.isAuthenticated) {
      // Fallback: return meeting as-is if not authenticated
      return meeting;
    }

    final body = {
      'title': meeting.title ?? 'Untitled Meeting',
      'transcript': meeting.transcript ?? '',
      'summary': meeting.summary ?? '',
      'workflow_count': meeting.workflowCount,
    };

    // If meeting has a server ID, it's an update; otherwise create
    if (meeting.id.isNotEmpty && !meeting.id.startsWith('local_')) {
      final response = await http.put(
        Uri.parse('${auth.apiUrl}/api/meetings/${meeting.id}'),
        headers: auth.authHeaders,
        body: jsonEncode(body),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return Meeting(
          id: data['id'] ?? meeting.id,
          title: data['title'] ?? meeting.title,
          date: meeting.date,
          summary: data['summary'] ?? meeting.summary,
          workflowCount: data['workflow_count'] ?? meeting.workflowCount,
          durationMinutes: meeting.durationMinutes,
          transcript: meeting.transcript,
          proposalJson: meeting.proposalJson,
        );
      }
    }

    // Create new meeting
    final response = await http.post(
      Uri.parse('${auth.apiUrl}/api/meetings'),
      headers: auth.authHeaders,
      body: jsonEncode(body),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return Meeting(
        id: data['id'] ?? meeting.id,
        title: data['title'] ?? meeting.title,
        date: meeting.date,
        summary: data['summary'] ?? meeting.summary,
        workflowCount: meeting.workflowCount,
        durationMinutes: meeting.durationMinutes,
        transcript: meeting.transcript,
        proposalJson: meeting.proposalJson,
      );
    }

    // Fallback — return meeting as-is
    return meeting;
  }

  /// Load all meetings from backend
  static Future<List<Meeting>> loadAll(AuthService auth) async {
    if (!auth.isAuthenticated) return [];

    try {
      final response = await http.get(
        Uri.parse('${auth.apiUrl}/api/meetings'),
        headers: auth.authHeaders,
      );

      if (response.statusCode == 200) {
        final List data = jsonDecode(response.body);
        return data.map((m) => Meeting(
          id: m['id'] ?? '',
          title: m['title'] ?? 'Untitled Meeting',
          date: DateTime.tryParse(m['created_at'] ?? '') ?? DateTime.now(),
          summary: m['summary'] != null ? m['summary'] as String? : null,
          workflowCount: (m['workflow_count'] as num?)?.toInt() ?? 0,
          durationMinutes: 0,
        )).toList();
      }
    } catch (_) {
      // Server unreachable — return empty
    }
    return [];
  }

  /// Delete a meeting by ID
  static Future<void> delete(String id, AuthService auth) async {
    if (!auth.isAuthenticated) return;

    await http.delete(
      Uri.parse('${auth.apiUrl}/api/meetings/$id'),
      headers: auth.authHeaders,
    );
  }

  /// Get a single meeting with full transcript
  static Future<Meeting?> get(String id, AuthService auth) async {
    if (!auth.isAuthenticated) return null;

    try {
      final response = await http.get(
        Uri.parse('${auth.apiUrl}/api/meetings/$id'),
        headers: auth.authHeaders,
      );

      if (response.statusCode == 200) {
        final m = jsonDecode(response.body);
        return Meeting(
          id: m['id'] ?? '',
          title: m['title'] ?? 'Untitled Meeting',
          date: DateTime.tryParse(m['created_at'] ?? '') ?? DateTime.now(),
          summary: m['summary'] as String?,
          workflowCount: (m['workflow_count'] as num?)?.toInt() ?? 0,
          durationMinutes: 0,
          transcript: m['transcript'] as String?,
        );
      }
    } catch (_) {}

    return null;
  }

  /// Clear all meetings — deletes each one individually
  static Future<void> clear(AuthService auth) async {
    final meetings = await loadAll(auth);
    for (final m in meetings) {
      await delete(m.id, auth);
    }
  }
}