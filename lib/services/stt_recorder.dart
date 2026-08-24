import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'js_interop.dart';

/// Platform-aware STT recorder.
/// On web: uses browser MediaRecorder API via JS interop
/// On mobile: uses record package for audio capture
class STTRecorder {
  bool _isRecording = false;
  Uint8List? _audioData;
  String _mimeType = 'audio/webm'; // default, updated from JS on web
  String _lastDebugState = ''; // visible debug state for UI

  bool get isRecording => _isRecording;
  String get debugState => _lastDebugState;

  /// Get the detected audio MIME type (overridden on web)
  String get mimeType => _mimeType;

  /// Start recording audio from the microphone
  Future<void> start() async {
    _isRecording = true;
    _audioData = null;
    _lastDebugState = '🎤 Injecting STT script...';

    if (kIsWeb) {
      // Web: inject MediaRecorder glue code and start recording
      injectSTTScript();
      
      _lastDebugState = '🎤 Calling getUserMedia...';
      // _clozrSTTStart() is async - it returns a Promise.
      // We poll for _clozrSTTStartStatus which tracks: 'pending' | 'success' | 'error'
      callJS('window._clozrSTTStart()');
      
      // Poll for the result - give up to 15 seconds for user to respond
      // to the browser permission prompt
      for (int i = 0; i < 150; i++) {
        await Future.delayed(const Duration(milliseconds: 100));
        
        final status = callJS('window._clozrSTTStartStatus');
        final statusStr = status?.toString() ?? '';
        
        if (statusStr == 'success') {
          // Verify recorder is actually running
          final isRecording = callJS('window._clozrSTTRecorder && window._clozrSTTRecorder.state === "recording"');
          if (isRecording == true) {
            _lastDebugState = '🎤 Recording active';
            return; // Success!
          }
          // Status says success but recorder not ready yet — keep polling briefly
          continue;
        }
        
        if (statusStr == 'error') {
          // getUserMedia failed — check the error message
          _isRecording = false;
          final error = callJS('window._clozrSTTError');
          final errorMsg = error?.toString() ?? 'Microphone access denied';
          _lastDebugState = '❌ Start error: $errorMsg';
          throw Exception(errorMsg);
        }
        
        // status == 'pending' — still waiting for user to respond to prompt
      }
      
      // Timeout - user probably didn't respond to the permission prompt
      _isRecording = false;
      _lastDebugState = '⏰ Mic permission timeout';
      throw Exception('Microphone access timed out. If you didn\'t see a permission prompt, try:\n'
          '1. Tap the lock/settings icon in your browser\'s address bar\n'
          '2. Go to Site settings → Microphone → Allow\n'
          '3. Refresh the page and try again');
    } else {
      // Mobile: will use record package via STTService
      // The record package handles mic permission request natively
    }
  }

  /// Stop recording and return audio bytes
  Future<Uint8List?> stop() async {
    _isRecording = false;

    if (kIsWeb) {
      return _stopWeb();
    } else {
      // Mobile: audio data comes from record package via STTService
      return _audioData;
    }
  }

  void setResult(Uint8List? data) {
    _audioData = data;
  }

  void cancel() {
    _isRecording = false;
    _audioData = null;
    _lastDebugState = '';
    if (kIsWeb) {
      callJS('window._clozrSTTCancel()');
    }
  }

  /// Check if recording is available on this platform
  bool get isAvailable => true;

  // Web: Stop recording and poll for audio bytes
  Future<Uint8List?> _stopWeb() async {
    // Clear any stale result before stopping (safety measure for second+ recordings)
    callJS('window._clozrSTTResult = null');
    
    // Check recorder state before stopping
    final recState = callJS('window._clozrSTTRecorder ? window._clozrSTTRecorder.state : "none"');
    final chunkCount = callJS('window._clozrSTTChunks ? window._clozrSTTChunks.length : 0');
    final stateStr = recState?.toString() ?? 'none';
    final chunksInt = chunkCount is int ? chunkCount : 0;
    debugPrint('[Clozr] Stop: recorder state=$stateStr, chunks=$chunksInt');
    _lastDebugState = '⏹ Stopping... state=$stateStr, chunks=$chunksInt';
    
    if (stateStr == 'inactive' || stateStr == 'none') {
      debugPrint('[Clozr] Stop: recorder already $stateStr');
      if (chunksInt > 0) {
        debugPrint('[Clozr] Stop: chunks exist ($chunksInt), creating blob from them');
        _lastDebugState = '⏹ Recorder inactive but $chunksInt chunks exist, recovering...';
        // Force blob creation from existing chunks even though recorder is inactive
        callJS('window._clozrSTTStop_fromInactive()');
      } else {
        _lastDebugState = '❌ No recorder and no chunks - audio lost';
        return null;
      }
    } else {
      callJS('window._clozrSTTStop()');
    }

    // Poll for result — the JS stop function sets window._clozrSTTResult
    // when the blob is ready (async because of arrayBuffer conversion)
    for (int i = 0; i < 100; i++) { // 10 second timeout
      await Future.delayed(const Duration(milliseconds: 100));
      try {
        final hasResult = callJS('window._clozrSTTResult !== null && window._clozrSTTResult !== undefined');
        if (hasResult == true) {
          // Check if result is empty
          final resultLen = callJS('window._clozrSTTResult.length');
          final lenInt = resultLen is int ? resultLen : -1;
          
          if (lenInt == 0) {
            debugPrint('[Clozr] Stop: got empty audio data - recorder was inactive');
            _lastDebugState = '❌ Empty audio (recorder was inactive before stop)';
            return null;
          }
          
          _lastDebugState = '📦 Converting ${lenInt} bytes to base64...';
          
          // SAFE base64 encoding: byte-by-byte loop (no apply() to avoid stack overflow)
          // 8KB sub-chunks for string building, each byte converted individually
          final base64Str = callJS(
            '(() => { try { var bytes = new Uint8Array(window._clozrSTTResult); var chunks = []; var chunkSize = 8192; for (var i = 0; i < bytes.length; i += chunkSize) { var chunk = bytes.subarray(i, Math.min(i + chunkSize, bytes.length)); var str = ""; for (var j = 0; j < chunk.length; j++) { str += String.fromCharCode(chunk[j]); } chunks.push(str); } return btoa(chunks.join("")); } catch(e) { console.error("base64 encode error:", e); return ""; } })()'
          ) as String;
          
          callJS('window._clozrSTTResult = null');

          if (base64Str.isEmpty) {
            debugPrint('[Clozr] Stop: base64 conversion failed');
            _lastDebugState = '❌ Base64 conversion failed';
            return null;
          }

          final bytes = base64Decode(base64Str);
          debugPrint('[Clozr] Stop: got ${bytes.length} bytes of audio data');
          _lastDebugState = '✅ Got ${bytes.length} bytes audio';
          _audioData = bytes;
          
          // Get the detected mime type (Safari = audio/mp4, Chrome = audio/webm)
          try {
            final detectedMime = callJS('window._clozrSTTMimeType || "audio/webm"');
            if (detectedMime != null && detectedMime.toString().isNotEmpty) {
              _mimeType = detectedMime.toString();
            }
          } catch (_) {}
          
          return bytes;
        }
      } catch (e) {
        debugPrint('[Clozr] Stop: poll error: $e');
        _lastDebugState = '⚠ Poll error: $e';
        // Keep polling
      }
    }

    debugPrint('[Clozr] Stop: timed out waiting for audio data after 10 seconds');
    _lastDebugState = '❌ Timed out waiting for audio (10s)';
    return null;
  }
}