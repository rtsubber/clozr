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
        window._clozrSTTResult = null; // Clear stale result from previous recording
        try {
          var stream = await navigator.mediaDevices.getUserMedia({audio: true, video: false});
          window._clozrSTTStream = stream;
          window._clozrSTTChunks = [];
          var options = {};
          window._clozrSTTMimeType = null;
          if (typeof MediaRecorder !== 'undefined') {
            if (MediaRecorder.isTypeSupported('audio/webm;codecs=opus')) {
              options = {mimeType: 'audio/webm;codecs=opus'};
              window._clozrSTTMimeType = 'audio/webm';
            } else if (MediaRecorder.isTypeSupported('audio/webm')) {
              options = {mimeType: 'audio/webm'};
              window._clozrSTTMimeType = 'audio/webm';
            } else if (MediaRecorder.isTypeSupported('audio/mp4')) {
              options = {mimeType: 'audio/mp4'};
              window._clozrSTTMimeType = 'audio/mp4';
            }
            // else: let browser choose default format
          }
          window._clozrSTTRecorder = new MediaRecorder(stream, options);
          window._clozrSTTRecorder.ondataavailable = function(e) {
            if (e.data.size > 0) {
              window._clozrSTTChunks.push(e.data);
            }
          };
          window._clozrSTTRecorder.onerror = function(e) {
            console.error('Clozr MediaRecorder error:', e.error || e);
            window._clozrSTTError = 'Recording error: ' + (e.error ? e.error.message : 'unknown');
          };
          window._clozrSTTRecorder.start(1000);
          console.log('Clozr: MediaRecorder started, state=' + window._clozrSTTRecorder.state + ', mimeType=' + (window._clozrSTTMimeType || 'default'));
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
        window._clozrSTTResult = null; // Clear before starting stop process
        if (!rec || rec.state === 'inactive') {
          console.error('Clozr: Recorder is ' + (!rec ? 'null' : 'inactive') + ' at stop time. Chunks: ' + window._clozrSTTChunks.length);
          window._clozrSTTResult = new Uint8Array(0);
          return;
        }
        var mimeType = window._clozrSTTMimeType || 'audio/webm';
        console.log('Clozr: Stopping recorder, chunks=' + window._clozrSTTChunks.length + ', state=' + rec.state);
        rec.onstop = function() {
          console.log('Clozr: Recorder stopped. Chunks: ' + window._clozrSTTChunks.length);
          var blobOptions = mimeType ? {type: mimeType} : {};
          try {
            var blob = new Blob(window._clozrSTTChunks, blobOptions);
          } catch(e) {
            console.error('Clozr: Blob creation error:', e);
            var blob = new Blob(window._clozrSTTChunks);
          }
          console.log('Clozr: Blob created, size=' + blob.size + ', type=' + blob.type);
          if (window._clozrSTTStream) {
            window._clozrSTTStream.getTracks().forEach(function(t) { t.stop(); });
          }
          // Store actual mime type for Safari (audio/mp4) vs Chrome (audio/webm)
          window._clozrSTTMimeType = blob.type || mimeType;
          blob.arrayBuffer().then(function(buf) {
            window._clozrSTTResult = new Uint8Array(buf);
            console.log('Clozr: Audio data ready, size=' + window._clozrSTTResult.length + ' bytes');
          }).catch(function(err) {
            console.error('Clozr: arrayBuffer error:', err);
            window._clozrSTTResult = new Uint8Array(0);
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

      // Handle the case where the recorder went inactive but chunks exist
      // (e.g., browser auto-stopped recording, second recording attempt)
      window._clozrSTTStop_fromInactive = function() {
        var mimeType = window._clozrSTTMimeType || 'audio/webm';
        console.log('Clozr: Recovering audio from ' + window._clozrSTTChunks.length + ' chunks (recorder was inactive)');
        try {
          var blob = new Blob(window._clozrSTTChunks, mimeType ? {type: mimeType} : {});
        } catch(e) {
          console.error('Clozr: Blob creation error in fromInactive:', e);
          var blob = new Blob(window._clozrSTTChunks);
        }
        window._clozrSTTMimeType = blob.type || mimeType;
        blob.arrayBuffer().then(function(buf) {
          window._clozrSTTResult = new Uint8Array(buf);
          console.log('Clozr: Recovered audio, size=' + window._clozrSTTResult.length + ' bytes');
        }).catch(function(err) {
          console.error('Clozr: arrayBuffer error in fromInactive:', err);
          window._clozrSTTResult = new Uint8Array(0);
        });
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