/// Web-only JS interop implementations using dart:js and dart:html.
/// These are only used on web; the stub file handles mobile.

import 'dart:js' as js;

void injectLiveTextScript() {
  // Start browser Web Speech API for live transcript preview.
  // This runs ALONGSIDE MediaRecorder — Speech API shows live text,
  // MediaRecorder captures audio for accurate Whisper transcription after.
  final jsCode = '''
    (function() {
      if (window._clozrLiveTextRecognition) {
        // Already running — just restart if stopped
        try { window._clozrLiveTextRecognition.start(); } catch(e) {}
        return;
      }
      var SpeechRecognition = window.SpeechRecognition || window.webkitSpeechRecognition;
      if (!SpeechRecognition) {
        window._clozrLiveText = '🎤 Recording... (live preview not supported in this browser)';
        return;
      }
      var recognition = new SpeechRecognition();
      recognition.continuous = true;
      recognition.interimResults = true;
      recognition.lang = 'en-US';
      recognition.maxAlternatives = 1;

      var fullTranscript = '';
      recognition.onresult = function(event) {
        var interim = '';
        for (var i = event.resultIndex; i < event.results.length; i++) {
          if (event.results[i].isFinal) {
            fullTranscript += event.results[i][0].transcript + ' ';
          } else {
            interim += event.results[i][0].transcript;
          }
        }
        window._clozrLiveText = (fullTranscript + interim).trim();
      };
      recognition.onerror = function(event) {
        // Don't set error text — just silently continue. The final transcript
        // from Whisper will be accurate regardless.
        console.log('Speech API error (non-fatal):', event.error);
      };
      recognition.onend = function() {
        // Auto-restart if still recording (Speech API stops after silence)
        if (window._clozrLiveTextRecognition) {
          try { recognition.start(); } catch(e) {}
        }
      };
      window._clozrLiveTextRecognition = recognition;
      window._clozrLiveText = '';
      recognition.start();
    })();
  ''';
  js.context.callMethod('eval', [jsCode]);
}

String? getLiveText() {
  try {
    final text = js.context.callMethod('eval', ['window._clozrLiveText || ""']);
    return text?.toString();
  } catch (e) {
    return null;
  }
}

void injectStopRecordingScript() {
  // Stop the Speech API recognition
  final jsCode = '''
    (function() {
      if (window._clozrLiveTextRecognition) {
        try { window._clozrLiveTextRecognition.stop(); } catch(e) {}
        window._clozrLiveTextRecognition = null;
      }
    })();
  ''';
  js.context.callMethod('eval', [jsCode]);
}

void injectResumeRecordingScript() {
  // Resume recording on web — restart Speech API
  injectLiveTextScript();
}

void injectSTTCancelScript() {
  js.context.callMethod('eval', ['window._clozrSTTCancel && window._clozrSTTCancel()']);
  // Also stop Speech API
  injectStopRecordingScript();
}

void injectPdfJsScript() {
  final jsCode = '''
    if (!window._clozrPdfJsLoaded) {
      window._clozrPdfJsLoaded = true;
    }
  ''';
  js.context.callMethod('eval', [jsCode]);
}

dynamic getPdfResult() {
  try {
    final result = js.context['window']['_clozrPdfResult'];
    return result;
  } catch (e) {
    return null;
  }
}

void clearPdfResult() {
  try {
    js.context['window']['_clozrPdfResult'] = null;
  } catch (e) {
    // Ignore on non-web
  }
}

void evalJs(String code) {
  try {
    js.context.callMethod('eval', [code]);
  } catch (e) {
    // Ignore on non-web
  }
}

/// Inject the STT MediaRecorder glue code into the page.
/// This sets up window._clozrSTTStart, _clozrSTTStop, _clozrSTTCancel
/// and the MediaRecorder-based audio capture for transcription.
void injectSTTScript() {
  // Use an IIFE to avoid top-level return issues and scope the code properly.
  // This is eval()'d as a single expression, so it must be valid JS.
  final jsCode = '''
    (function() {
      if (window._clozrSTTReady) return;
      window._clozrSTTReady = true;
      window._clozrSTTRecorder = null;
      window._clozrSTTStream = null;
      window._clozrSTTChunks = [];
      window._clozrSTTResult = null;
      window._clozrSTTError = null;
      window._clozrSTTStartStatus = 'pending';

      window._clozrSTTStart = async function() {
        window._clozrSTTError = null;
        window._clozrSTTStartStatus = 'pending';
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
          window._clozrSTTStartStatus = 'success';
        } catch (e) {
          console.error('STT start error:', e.name, e.message);
          window._clozrSTTStartStatus = 'error';
          if (e.name === 'NotAllowedError' || e.name === 'PermissionDeniedError') {
            window._clozrSTTError = 'Microphone permission denied. Please allow microphone in browser settings and try again.';
          } else if (e.name === 'NotFoundError') {
            window._clozrSTTError = 'No microphone found. Please connect a microphone.';
          } else if (e.name === 'NotReadableError' || e.name === 'AbortError') {
            window._clozrSTTError = 'Microphone is in use by another app.';
          } else {
            window._clozrSTTError = 'Microphone error: ' + e.message;
          }
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
        if (window._clozrSTTStream) {
          window._clozrSTTStream.getTracks().forEach(function(t) { t.stop(); });
        }
      };
    })();
  ''';
  js.context.callMethod('eval', [jsCode]);
}

/// Evaluate a JS expression and return the result.
dynamic callJS(String code) {
  try {
    return js.context.callMethod('eval', [code]);
  } catch (e) {
    return null;
  }
}