import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'js_interop.dart';

/// Platform-aware STT recorder.
/// On web: uses browser MediaRecorder API via JS interop
/// On mobile: uses record package for audio capture
class STTRecorder {
  bool _isRecording = false;
  Uint8List? _audioData;

  bool get isRecording => _isRecording;

  /// Start recording audio from the microphone
  Future<void> start() async {
    _isRecording = true;
    _audioData = null;

    if (kIsWeb) {
      // Web: inject MediaRecorder glue code and start recording
      injectSTTScript();
      
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
          throw Exception(errorMsg);
        }
        
        // status == 'pending' — still waiting for user to respond to prompt
      }
      
      // Timeout - user probably didn't respond to the permission prompt
      _isRecording = false;
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
    if (kIsWeb) {
      callJS('window._clozrSTTCancel()');
    }
  }

  /// Check if recording is available on this platform
  bool get isAvailable => true;

  // Web: Stop recording and poll for audio bytes
  Future<Uint8List?> _stopWeb() async {
    callJS('window._clozrSTTStop()');

    // Poll for result — the JS stop function sets window._clozrSTTResult
    // when the blob is ready (async because of arrayBuffer conversion)
    for (int i = 0; i < 100; i++) { // 10 second timeout
      await Future.delayed(const Duration(milliseconds: 100));
      try {
        final hasResult = callJS('window._clozrSTTResult !== null && window._clozrSTTResult !== undefined');
        if (hasResult == true) {
          final byteLength = callJS('window._clozrSTTResult.length') as int;

          if (byteLength == 0) {
            callJS('window._clozrSTTResult = null');
            return Uint8List(0);
          }

          // Use base64 to transfer binary data from JS to Dart safely.
          // Direct char code extraction fails for bytes >= 128 (WebM/Opus audio).
          final base64Str = callJS(
            'btoa(String.fromCharCode.apply(null, new Uint8Array(window._clozrSTTResult)))'
          ) as String;
          
          callJS('window._clozrSTTResult = null');

          final bytes = base64Decode(base64Str);
          _audioData = bytes;
          return bytes;
        }
      } catch (e) {
        // Keep polling
      }
    }

    return null;
  }
}