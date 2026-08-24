import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Cache transcripts locally so they're never lost even if backend save fails.
class LocalTranscriptCache {
  static const String _keyPrefix = 'clozr_transcript_';
  static const int _maxCached = 10;

  /// Save transcript to local cache
  static Future<void> save(String transcript, {String? title, String? meetingId}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final id = meetingId ?? DateTime.now().millisecondsSinceEpoch.toString();
      final data = {
        'id': id,
        'title': title ?? 'Meeting ${DateTime.now().month}/${DateTime.now().day}',
        'transcript': transcript,
        'savedAt': DateTime.now().toIso8601String(),
      };
      
      // Get existing list
      final keys = prefs.getStringList('${_keyPrefix}keys') ?? [];
      keys.insert(0, id);
      if (keys.length > _maxCached) {
        // Remove oldest
        final toRemove = keys.sublist(_maxCached);
        for (final k in toRemove) {
          await prefs.remove('${_keyPrefix}$k');
        }
        keys.removeRange(_maxCached, keys.length);
      }
      
      await prefs.setString('${_keyPrefix}$id', jsonEncode(data));
      await prefs.setStringList('${_keyPrefix}keys', keys);
    } catch (_) {
      // Local save failed - nothing we can do
    }
  }

  /// Get all cached transcripts
  static Future<List<Map<String, dynamic>>> getAll() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getStringList('${_keyPrefix}keys') ?? [];
      final results = <Map<String, dynamic>>[];
      
      for (final key in keys) {
        final jsonStr = prefs.getString('${_keyPrefix}$key');
        if (jsonStr != null) {
          results.add(jsonDecode(jsonStr) as Map<String, dynamic>);
        }
      }
      return results;
    } catch (_) {
      return [];
    }
  }

  /// Delete a cached transcript
  static Future<void> delete(String id) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getStringList('${_keyPrefix}keys') ?? [];
      keys.remove(id);
      await prefs.remove('${_keyPrefix}$id');
      await prefs.setStringList('${_keyPrefix}keys', keys);
    } catch (_) {}
  }

  /// Check if there are any cached transcripts
  static Future<bool> hasCached() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getStringList('${_keyPrefix}keys') ?? [];
      return keys.isNotEmpty;
    } catch (_) {
      return false;
    }
  }
}
