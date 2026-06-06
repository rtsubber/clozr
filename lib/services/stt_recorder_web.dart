library stt_recorder_web;

import 'dart:async';
import 'dart:js' as js;
import 'dart:html' as html;
import 'dart:typed_data';

/// Web implementation of audio recording using MediaRecorder API.
/// Records WebM/Opus audio and returns raw bytes via injected JS glue code.
class STTRecorder {
  bool _isRecording = false;
  Uint8List? _recordedBytes;

  bool get isRecording => _isRecording;

  static bool get isSupported {
    try {
      return js.context.hasProperty('MediaRecorder');
    } catch (_) {
      return false;
    }
  }

  /// Start recording audio from the microphone
  Future<void> start() async {
    _ensureGlueCode();
    _recordedBytes = null;

    final result = js.context.callMethod('eval', ['window._clozrSTTStart()']);
    if (result == false || result == null) {
      throw Exception('Microphone access denied or MediaRecorder not supported');
    }
    _isRecording = true;
  }

  /// Stop recording and return audio bytes
  Future<Uint8List> stop() async {
    _isRecording = false;

    // Call stop which triggers blob conversion and stores result
    js.context.callMethod('eval', ['window._clozrSTTStop()']);

    // Poll for result — the JS stop function sets window._clozrSTTResult
    // when the blob is ready (async because of arrayBuffer conversion)
    for (int i = 0; i < 80; i++) { // 8 second timeout
      await Future.delayed(const Duration(milliseconds: 100));
      try {
        final hasResult = js.context.callMethod('eval', [
          'window._clozrSTTResult !== null && window._clozrSTTResult !== undefined'
        ]);
        if (hasResult == true) {
          // Extract bytes using a helper function that avoids minification issues
          final byteLength = js.context.callMethod('eval', [
            'window._clozrSTTResult.length'
          ]) as int;
          
          if (byteLength == 0) {
            js.context.callMethod('eval', ['window._clozrSTTResult = null']);
            return Uint8List(0);
          }
          
          // Copy bytes using a JS slice + base64 approach to avoid minification
          final base64 = js.context.callMethod('eval', [
            'Array.from(window._clozrSTTResult).map(function(b){return String.fromCharCode(b)}).join("")'
          ]) as String;
          
          // Clear the result
          js.context.callMethod('eval', ['window._clozrSTTResult = null']);
          
          // Convert base64-like string to bytes
          final bytes = Uint8List(byteLength);
          for (int j = 0; j < byteLength && j < base64.length; j++) {
            bytes[j] = base64.codeUnitAt(j) & 0xFF;
          }
          
          return bytes;
        }
      } catch (e) {
        // Keep polling
      }
    }

    return Uint8List(0);
  }

  /// Cancel recording without returning data
  void cancel() {
    _isRecording = false;
    try {
      js.context.callMethod('eval', ['window._clozrSTTCancel()']);
    } catch (_) {}
  }

  void _ensureGlueCode() {
    if (js.context.hasProperty('_clozrSTTReady')) return;

    final script = html.ScriptElement();
    script.type = 'text/javascript';
    script.text = _glueCode;
    html.document.head!.append(script);
  }

  static const _glueCode = '''
    window._clozrSTTReady = true;
    window._clozrSTTRecorder = null;
    window._clozrSTTStream = null;
    window._clozrSTTChunks = [];
    window._clozrSTTResult = null;
    
    window._clozrSTTStart = async function() {
      try {
        var stream = await navigator.mediaDevices.getUserMedia({audio: true, video: false});
        window._clozrSTTStream = stream;
        window._clozrSTTChunks = [];
        var options = {mimeType: 'audio/webm;codecs=opus'};
        if (typeof MediaRecorder !== 'undefined' && !MediaRecorder.isTypeSupported(options.mimeType)) {
          options = {};
        }
        window._clozrSTTRecorder = new MediaRecorder(stream, options);
        window._clozrSTTRecorder.ondataavailable = function(e) {
          if (e.data.size > 0) {
            window._clozrSTTChunks.push(e.data);
          }
        };
        window._clozrSTTRecorder.start(1000);
        return true;
      } catch (e) {
        console.error('STT start error:', e);
        return false;
      }
    };
    
    window._clozrSTTStop = function() {
      var rec = window._clozrSTTRecorder;
      if (!rec || rec.state === 'inactive') {
        window._clozrSTTResult = new Uint8Array(0);
        return;
      }
      rec.onstop = function() {
        var blob = new Blob(window._clozrSTTChunks);
        if (window._clozrSTTStream) {
          window._clozrSTTStream.getTracks().forEach(function(t) { t.stop(); });
        }
        blob.arrayBuffer().then(function(buf) {
          window._clozrSTTResult = new Uint8Array(buf);
        });
      };
      rec.stop();
    };
    
    window._clozrSTTCancel = function() {
      var rec = window._clozrSTTRecorder;
      if (rec && rec.state !== 'inactive') {
        rec.stop();
      }
      if (window._clozzSTTStream) {
        window._clozrSTTStream.getTracks().forEach(function(t) { t.stop(); });
      }
    };
  ''';
}