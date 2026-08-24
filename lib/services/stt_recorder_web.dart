library stt_recorder_web;

import 'dart:async';
import 'dart:convert';
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

    // Poll for result — the JS stop function sets window._clozrSTTResultBase64
    // when the blob is ready (async because of arrayBuffer conversion)
    for (int i = 0; i < 80; i++) { // 8 second timeout
      await Future.delayed(const Duration(milliseconds: 100));
      try {
        final hasResult = js.context.callMethod('eval', [
          'window._clozrSTTResultBase64 !== null && window._clozrSTTResultBase64 !== undefined'
        ]);
        if (hasResult == true) {
          // Get base64 string from JS — this preserves binary data correctly
          final base64Str = js.context.callMethod('eval', [
            'window._clozrSTTResultBase64'
          ]) as String;
          
          // Clear the result
          js.context.callMethod('eval', ['window._clozrSTTResultBase64 = null']);
          js.context.callMethod('eval', ['window._clozrSTTResult = null']);
          
          if (base64Str.isEmpty) {
            return Uint8List(0);
          }
          
          // Decode base64 to bytes — proper binary transfer
          return _base64Decode(base64Str);
        }
      } catch (e) {
        // Keep polling
      }
    }

    return Uint8List(0);
  }

  /// Decode base64 string to Uint8List
  Uint8List _base64Decode(String base64Str) {
    // Use dart:convert's base64 decoder
    return base64Decode(base64Str);
  }

  /// Get the detected audio MIME type (e.g. 'audio/webm' or 'audio/mp4' for Safari)
  String get mimeType {
    try {
      final mt = js.context.callMethod('eval', ['window._clozrSTTMimeType || "audio/webm"']);
      return mt as String? ?? 'audio/webm';
    } catch (_) {
      return 'audio/webm';
    }
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
    window._clozrSTTMimeType = null; // Track actual mime type for Safari
    
    window._clozrSTTStart = async function() {
      try {
        // Safari requires HTTPS for getUserMedia (we have that via Cloudflare)
        if (!navigator.mediaDevices || !navigator.mediaDevices.getUserMedia) {
          console.error('getUserMedia not available (requires HTTPS)');
          return false;
        }
        
        var stream = await navigator.mediaDevices.getUserMedia({
          audio: {
            echoCancellation: true,
            noiseSuppression: true,
            autoGainControl: true
          },
          video: false
        });
        window._clozrSTTStream = stream;
        window._clozrSTTChunks = [];
        
        // Safari compatibility: prefer webm/opus, fall back to mp4/aac, then default
        var options = {};
        var mimeType = null;
        if (typeof MediaRecorder !== 'undefined') {
          if (MediaRecorder.isTypeSupported('audio/webm;codecs=opus')) {
            options = {mimeType: 'audio/webm;codecs=opus'};
            mimeType = 'audio/webm';
          } else if (MediaRecorder.isTypeSupported('audio/webm')) {
            options = {mimeType: 'audio/webm'};
            mimeType = 'audio/webm';
          } else if (MediaRecorder.isTypeSupported('audio/mp4')) {
            // Safari 14.1+ records as audio/mp4 (AAC)
            options = {mimeType: 'audio/mp4'};
            mimeType = 'audio/mp4';
          } else if (MediaRecorder.isTypeSupported('audio/aac')) {
            options = {mimeType: 'audio/aac'};
            mimeType = 'audio/aac';
          }
          // else: let browser choose default format
        }
        window._clozrSTTMimeType = mimeType;
        console.log('Clozr recording format:', mimeType || 'browser default');
        
        window._clozrSTTRecorder = new MediaRecorder(stream, options);
        window._clozrSTTRecorder.ondataavailable = function(e) {
          if (e.data.size > 0) {
            window._clozrSTTChunks.push(e.data);
          }
        };
        window._clozrSTTRecorder.onerror = function(e) {
          console.error('MediaRecorder error:', e.error);
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
        window._clozrSTTResultBase64 = ''; // Signal: empty result
        return;
      }
      var mimeType = window._clozrSTTMimeType || 'audio/webm';
      rec.onstop = function() {
        // Use the detected mime type for the blob
        // Safari records as audio/mp4, Chrome as audio/webm
        var blobOptions = mimeType ? {type: mimeType} : {};
        try {
          var blob = new Blob(window._clozrSTTChunks, blobOptions);
        } catch(e) {
          // Fallback: no mime type
          var blob = new Blob(window._clozrSTTChunks);
        }
        if (window._clozrSTTStream) {
          window._clozrSTTStream.getTracks().forEach(function(t) { t.stop(); });
        }
        
        console.log('Clozr: blob size=' + blob.size + ', type=' + blob.type);
        
        // Convert blob to base64 for safe transfer to Dart
        // (Direct byte transfer via charCodeAt corrupts bytes > 127)
        function arrayBufferToBase64(buffer) {
          var bytes = new Uint8Array(buffer);
          var binary = '';
          var chunkSize = 32768; // Process in chunks to avoid stack overflow
          for (var i = 0; i < bytes.length; i += chunkSize) {
            var chunk = bytes.subarray(i, Math.min(i + chunkSize, bytes.length));
            binary += String.fromCharCode.apply(null, chunk);
          }
          return btoa(binary);
        }
        
        // Safari 14.1+ supports blob.arrayBuffer()
        if (blob.arrayBuffer && typeof blob.arrayBuffer === 'function') {
          blob.arrayBuffer().then(function(buf) {
            try {
              window._clozrSTTResultBase64 = arrayBufferToBase64(buf);
              window._clozrSTTMimeType = blob.type || mimeType;
              console.log('Clozr: base64 encoded, length=' + window._clozrSTTResultBase64.length);
            } catch(err) {
              console.error('Clozr: base64 encode error:', err);
              window._clozrSTTResultBase64 = '';
            }
          }).catch(function(err) {
            console.error('Clozr: arrayBuffer error:', err);
            window._clozrSTTResultBase64 = '';
          });
        } else {
          // FileReader fallback for older browsers
          var reader = new FileReader();
          reader.onload = function() {
            try {
              window._clozrSTTResultBase64 = arrayBufferToBase64(reader.result);
              window._clozrSTTMimeType = blob.type || mimeType;
            } catch(err) {
              console.error('Clozr: FileReader base64 error:', err);
              window._clozrSTTResultBase64 = '';
            }
          };
          reader.readAsArrayBuffer(blob);
        }
      };
      rec.stop();
    };
    
    window._clozrSTTCancel = function() {
      var rec = window._clozrSTTRecorder;
      if (rec && rec.state !== 'inactive') {
        rec.stop();
      }
      if (window._clozrSTTStream) {
        window._clozrSTTStream.getTracks().forEach(function(t) { t.stop(); });
      }
    };
  ''';
}