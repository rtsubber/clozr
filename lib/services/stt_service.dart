import 'dart:async';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'auth_service.dart';
import 'stt_recorder.dart';
import '../models/meeting.dart';

/// Server-side Speech-to-Text service via Groq Whisper API.
/// Replaces browser Web Speech API (A6 fix).
///
/// Flow:
/// 1. Record audio using platform-specific recorder (WebM/Opus on web)
/// 2. Upload to backend /api/stt endpoint
/// 3. Backend proxies to Groq Whisper large-v3
/// 4. Returns transcript with timestamps
///
/// With diarization: uses /api/stt/diarize endpoint (Deepgram nova-3)
/// Returns speaker-labeled segments.
class STTService {
  final AuthService _auth;
  final STTRecorder _recorder = STTRecorder();

  bool _isRecording = false;
  String _transcript = '';
  bool _enableDiarization = false; // Toggle for speaker diarization

  Function(String text)? onTranscript;
  Function(String text)? onInterim;

  STTService(this._auth, {bool enableDiarization = false}) : _enableDiarization = enableDiarization;

  bool get isRecording => _isRecording;
  String get transcript => _transcript;
  bool get enableDiarization => _enableDiarization;
  set enableDiarization(bool v) => _enableDiarization = v;

  /// Start recording audio from microphone
  Future<void> startRecording({
    Function(String text)? onTranscript,
    Function(String text)? onInterim,
  }) async {
    if (_isRecording) return;

    this.onTranscript = onTranscript;
    this.onInterim = onInterim;

    await _recorder.start();
    _isRecording = true;
  }

  /// Stop recording and transcribe via server
  Future<Map<String, dynamic>> stopRecording() async {
    if (!_isRecording) {
      return {'transcript': '', 'segments': []};
    }

    _isRecording = false;

    try {
      final audioData = await _recorder.stop();
      
      if (audioData == null || audioData.isEmpty) {
        return {'transcript': '', 'segments': []};
      }

      // Upload to backend for transcription
      return await _transcribeAudio(audioData);
    } catch (e) {
      _isRecording = false;
      rethrow;
    }
  }

  /// Upload audio to backend for transcription via Groq Whisper or Deepgram
  Future<Map<String, dynamic>> _transcribeAudio(Uint8List audioData) async {
    if (!_auth.isAuthenticated) {
      throw Exception('Not authenticated. Please log in.');
    }

    // Choose endpoint based on diarization toggle
    final endpoint = _enableDiarization ? '/api/stt/diarize' : '/api/stt';
    final uri = Uri.parse('${_auth.apiUrl}$endpoint');
    final request = http.MultipartRequest('POST', uri)
      ..headers.addAll(_auth.authHeaders)
      ..files.add(http.MultipartFile.fromBytes(
        'audio',
        audioData,
        filename: 'recording.webm',
      ));

    final response = await request.send();
    final responseBody = await response.stream.bytesToString();

    if (response.statusCode == 200) {
      final data = jsonDecode(responseBody) as Map<String, dynamic>;
      _transcript = data['transcript'] as String? ?? '';

      if (_transcript.isNotEmpty && onTranscript != null) {
        onTranscript!(_transcript);
      }

      return data;
    }

    if (response.statusCode == 401) {
      throw Exception('Session expired. Please log in again.');
    }

    // If diarization fails (e.g. no Deepgram key), fallback to regular STT
    if (_enableDiarization && response.statusCode == 503) {
      _enableDiarization = false;
      return _transcribeAudio(audioData);
    }

    throw Exception('Transcription failed: ${response.statusCode}');
  }

  /// Cancel recording without transcribing
  void cancelRecording() {
    _isRecording = false;
    _recorder.cancel();
  }
}