import 'dart:convert';
import 'dart:io' as io;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart' as path_provider;
import '../services/js_interop.dart';
import '../services/stt_service.dart';
import '../services/llm_service.dart';
import '../services/workflow_service.dart';
import '../services/meeting_storage.dart';
import '../models/meeting.dart';
import '../models/workflow.dart';
import '../screens/proposal_screen.dart';
import '../screens/followup_email_screen.dart';
import '../main.dart';

class MeetingScreen extends ConsumerStatefulWidget {
  final String? meetingId;

  const MeetingScreen({super.key, this.meetingId});

  @override
  ConsumerState<MeetingScreen> createState() => _MeetingScreenState();
}

class _MeetingScreenState extends ConsumerState<MeetingScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isRecording = false;
  String _transcript = '';
  String _interimText = '';
  List<Workflow> _detectedWorkflows = [];
  String _summary = '';
  bool _isAnalyzing = false;
  String? _errorMessage;
  bool _isSaved = false;
  String? _savedMeetingId;
  bool _hasAudio = false;
  bool _isPlayingAudio = false;
  bool _livePreview = true; // Show live text while recording
  String? _audioFilename;
  double _audioDuration = 0.0;
  bool _enableDiarization = true; // Speaker diarization ON by default
  List<DiarizedSegment> _diarizedSegments = [];
  Map<String, String> _speakers = {}; // {"0": "Ron", "1": "Client"}
  bool _hasDiarization = false;

  AudioPlayer? _audioPlayer;

  void _toggleAudioPlayback() async {
    if (_savedMeetingId == null) return;
    final auth = ref.read(authProvider);
    final audioUrl = '${auth.apiUrl}/api/meetings/$_savedMeetingId/audio';

    if (_audioPlayer != null && _audioPlayer!.state == PlayerState.playing) {
      await _audioPlayer!.pause();
      setState(() { _isPlayingAudio = false; });
      return;
    }

    setState(() { _isPlayingAudio = true; });

    try {
      if (kIsWeb) {
        // On web, use js_interop to inject an audio player script
        // that fetches with auth headers (browser fetch supports headers)
        final escapedToken = (auth.token ?? '').replaceAll("'", "\\'");
        final jsCode = '''
          (function() {
            var audio = document.getElementById('clozr-audio-player');
            if (audio \u0026\u0026 !audio.paused) {
              audio.pause();
              audio.currentTime = 0;
              return;
            }
            fetch("$audioUrl", {
              headers: { "Authorization": "Bearer $escapedToken" }
            })
            .then(function(response) {
              if (!response.ok) throw new Error('Audio fetch failed: ' + response.status);
              return response.blob();
            })
            .then(function(blob) {
              var blobUrl = URL.createObjectURL(blob);
              if (!audio) {
                audio = document.createElement('audio');
                audio.id = 'clozr-audio-player';
                audio.style.display = 'none';
                document.body.appendChild(audio);
              }
              audio.src = blobUrl;
              audio.onended = function() {
                URL.revokeObjectURL(blobUrl);
              };
              audio.play();
            });
          })();
        ''';
        evalJs(jsCode);
      } else {
        // On mobile, download audio bytes then play with audioplayers
        final response = await http.get(
          Uri.parse(audioUrl),
          headers: auth.authHeaders,
        );
        if (response.statusCode == 200) {
          final tempDir = await path_provider.getTemporaryDirectory();
          final tempFile = io.File('${tempDir.path}/meeting_audio_$_savedMeetingId.wav');
          await tempFile.writeAsBytes(response.bodyBytes);
          _audioPlayer = AudioPlayer();
          await _audioPlayer!.play(UrlSource(tempFile.path));
          _audioPlayer!.onPlayerComplete.listen((_) {
            setState(() { _isPlayingAudio = false; });
          });
          _audioPlayer!.onPlayerStateChanged.listen((state) {
            if (state == PlayerState.paused || state == PlayerState.completed) {
              setState(() { _isPlayingAudio = false; });
            }
          });
        } else {
          setState(() { _isPlayingAudio = false; });
        }
      }
    } catch (_) {
      setState(() { _isPlayingAudio = false; });
    }
  }

  void _startLivePreview() {
    // On web, use browser Web Speech API for live interim text while recording.
    // The final accurate transcript comes from Groq Whisper after stopping.
    // On mobile, we show a static placeholder while the native recorder runs.
    try {
      if (kIsWeb) {
        injectLiveTextScript();
      }
      // Poll for live text (on mobile, poll returns null so static text stays)
      _pollLivePreview();
    } catch (_) {
      setState(() { _interimText = '🎤 Recording... Tap stop when done'; });
    }
  }

  void _pollLivePreview() async {
    while (_isRecording) {
      await Future.delayed(const Duration(milliseconds: 300));
      try {
        final text = kIsWeb ? getLiveText() : null;
        if (text != null && text.isNotEmpty) {
          setState(() { _interimText = text; });
        }
      } catch (_) {}
    }
  }

  void _stopLivePreview() {
    try {
      if (kIsWeb) {
        injectStopRecordingScript();
      }
    } catch (_) {}
    // Clear interim text on all platforms
    setState(() { _interimText = ''; });
  }

  STTService? _sttService;
  late LLMService _llmService;
  late WorkflowService _workflowService;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    // If a meetingId was passed, load the existing meeting
    if (widget.meetingId != null) {
      _loadExistingMeeting();
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _audioPlayer?.dispose();
    _sttService?.cancelRecording();
    super.dispose();
  }

  Future<void> _loadExistingMeeting() async {
    final auth = ref.read(authProvider);
    if (!auth.isAuthenticated || widget.meetingId == null) return;

    try {
      final response = await http.get(
        Uri.parse('${auth.apiUrl}/api/meetings/${widget.meetingId}'),
        headers: auth.authHeaders,
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final diarizedSegmentsData = data['diarized_segments'] as List? ?? [];
        final speakersData = (data['speakers'] as Map<String, dynamic>?)?.map((k, v) => MapEntry(k, v.toString())) ?? {};
        setState(() {
          _transcript = data['transcript'] as String? ?? '';
          _summary = data['summary'] as String? ?? '';
          _hasAudio = data['has_audio'] as bool? ?? false;
          _isSaved = true;
          _savedMeetingId = widget.meetingId;
          _isAnalyzing = false;
          _diarizedSegments = diarizedSegmentsData.map((s) => DiarizedSegment.fromJson(s as Map<String, dynamic>)).toList();
          _speakers = speakersData;
          _hasDiarization = data['has_diarization'] as bool? ?? false;
        });
      }
    } catch (_) {
      // Silently fail
    }
  }

  Future<void> _toggleRecording() async {
    if (_isRecording) {
      setState(() => _isRecording = false);
      
      // Stop live preview
      _stopLivePreview();
      
      if (_sttService != null) {
        try {
          // Stop recording and transcribe via server
          setState(() => _isAnalyzing = true);
          final result = await _sttService!.stopRecording();
          final transcript = result['transcript'] as String? ?? '';
          // segments available if needed: result['segments'] as List? ?? [];
          final duration = (result['duration'] as num?)?.toDouble() ?? 0.0;
          final meetingId = result['meeting_id'] as String? ?? _savedMeetingId;
          final audioFilename = result['audio_filename'] as String?;
          // Parse diarization data
          final diarizedSegmentsData = result['diarized_segments'] as List? ?? [];
          final speakersData = (result['speakers'] as Map<String, dynamic>?)?.map((k, v) => MapEntry(k, v.toString())) ?? {};
          final diarizedSegments = diarizedSegmentsData.map((s) => DiarizedSegment.fromJson(s as Map<String, dynamic>)).toList();
          setState(() {
            _transcript = transcript;
            _isAnalyzing = false;
            _hasAudio = transcript.isNotEmpty;
            _audioFilename = audioFilename;
            _audioDuration = duration;
            _diarizedSegments = diarizedSegments;
            _speakers = speakersData;
            _hasDiarization = diarizedSegments.isNotEmpty;
            if (meetingId != null) _savedMeetingId = meetingId;
          });

          if (transcript.trim().isNotEmpty) {
            // Save meeting with transcript
            final savedMeeting = await _saveMeetingToBackend(transcript, meetingId);
            if (savedMeeting != null) {
              setState(() { _savedMeetingId = savedMeeting; });
            }
            await _analyzeTranscript();
          }
        } catch (e) {
          setState(() {
            _isAnalyzing = false;
            _errorMessage = 'Transcription failed: $e';
          });
        }
      }
    } else {
      // Check auth before recording (STT requires auth)
      final auth = ref.read(authProvider);
      if (!auth.isAuthenticated) {
        setState(() {
          _errorMessage = 'Please sign in to record meetings.';
        });
        return;
      }

      setState(() {
        _isRecording = true;
        _errorMessage = null;
        _transcript = '';
        _interimText = '';
        _detectedWorkflows = [];
        _summary = '';
        _diarizedSegments = [];
        _speakers = {};
        _hasDiarization = false;
      });

      try {
        _sttService = STTService(auth, enableDiarization: _enableDiarization);
        await _sttService!.startRecording(
          onInterim: (text) {
            setState(() { _interimText = text; });
          },
        );

        if (_livePreview) {
          // Start browser Web Speech for live text preview
          _startLivePreview();
        } else {
          setState(() { _interimText = '🎤 Recording... Tap stop when done'; });
        }
      } catch (e) {
        final errMsg = e.toString();
        String userMessage;
        if (errMsg.contains('denied') || errMsg.contains('NotAllowed')) {
          userMessage = '🎤 Microphone blocked. To fix:\n\n'
              '📱 Chrome: Tap the lock/ⓘ icon in address bar → Site settings → Microphone → Allow\n'
              '📱 Safari: Settings app → Websites → Microphone → Allow for this site\n'
              '💻 Desktop: Click the camera icon in address bar → Allow microphone\n\n'
              'Then refresh the page and try again.';
        } else if (errMsg.contains('NotFound')) {
          userMessage = '🎤 No microphone found. Please connect a microphone and try again.';
        } else if (errMsg.contains('NotReadable') || errMsg.contains('Abort')) {
          userMessage = '🎤 Microphone is in use by another app. Close other apps using the mic and try again.';
        } else if (errMsg.contains('timed out')) {
          userMessage = errMsg; // Already has detailed instructions from stt_recorder
        } else {
          userMessage = 'Recording error: $errMsg';
        }
        setState(() {
          _isRecording = false;
          _errorMessage = userMessage;
        });
      }
    }
  }

  Future<void> _analyzeTranscript() async {
    if (_transcript.trim().isEmpty) return;
    final auth = ref.read(authProvider);
    if (!auth.isAuthenticated) {
      setState(() {
        _errorMessage = 'Please sign in to enable AI analysis.';
        _isAnalyzing = false;
      });
      return;
    }
    // Initialize services with auth
    _llmService = LLMService(auth);
    _workflowService = WorkflowService(auth);
    setState(() => _isAnalyzing = true);
    try {
      final results = await Future.wait([
        _llmService.summarizeMeeting(_transcript),
        _workflowService.detectWorkflows(_transcript),
      ]);
      setState(() {
        _summary = results[0] as String;
        _detectedWorkflows = results[1] as List<Workflow>;
        _isAnalyzing = false;
      });
    } catch (e) {
      setState(() {
        _isAnalyzing = false;
        _errorMessage = 'Analysis failed: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D12),
      body: SafeArea(
        child: Column(
          children: [
            // ── App Bar ──
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.arrow_back_ios_new, size: 20),
                    style: IconButton.styleFrom(foregroundColor: const Color(0xFF8B8BA0)),
                  ),
                  const Expanded(
                    child: Text('Meeting', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                  ),
                  if (_detectedWorkflows.isNotEmpty) _proposalButton(),
                  if (_detectedWorkflows.isNotEmpty) _followUpButton(),
                ],
              ),
            ),

            // ── Error Message ──
            if (_errorMessage != null) _errorBanner(),

            // ── Live Recording Indicator ──
            if (_isRecording) _recordingIndicator(),

            // ── Diarization toggle (before recording) ──
            if (!_isRecording && _transcript.isEmpty) Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
              child: GestureDetector(
                onTap: () => setState(() => _enableDiarization = !_enableDiarization),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF16161D),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: _enableDiarization ? const Color(0xFF6C5CE7) : const Color(0xFF2A2A3A)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.people_outline, size: 16,
                          color: _enableDiarization ? const Color(0xFF6C5CE7) : const Color(0xFF8B8BA0)),
                      const SizedBox(width: 8),
                      Text('Speaker Detection',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500,
                              color: _enableDiarization ? const Color(0xFF6C5CE7) : const Color(0xFF8B8BA0))),
                      const SizedBox(width: 8),
                      Container(
                        width: 36, height: 20,
                        decoration: BoxDecoration(
                          color: _enableDiarization ? const Color(0xFF6C5CE7) : const Color(0xFF2A2A3A),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: AnimatedAlign(
                          alignment: _enableDiarization ? Alignment.centerRight : Alignment.centerLeft,
                          duration: const Duration(milliseconds: 200),
                          child: Container(
                            width: 16, height: 16,
                            margin: const EdgeInsets.symmetric(horizontal: 2),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // ── Tab Bar ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF16161D),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: TabBar(
                  controller: _tabController,
                  dividerColor: Colors.transparent,
                  labelColor: const Color(0xFF6C5CE7),
                  unselectedLabelColor: const Color(0xFF8B8BA0),
                  indicator: BoxDecoration(
                    color: const Color(0xFF6C5CE7).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  indicatorSize: TabBarIndicatorSize.tab,
                  indicatorPadding: const EdgeInsets.all(4),
                  tabs: const [
                    Tab(text: 'Transcript', height: 36),
                    Tab(text: 'Workflows', height: 36),
                    Tab(text: 'Summary', height: 36),
                  ],
                ),
              ),
            ),

            // ── Tab Content ──
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _transcriptTab(),
                  _workflowsTab(),
                  _summaryTab(),
                ],
              ),
            ),

            // ── Bottom Bar ──
            _bottomBar(),
          ],
        ),
      ),
    );
  }

  Widget _errorBanner() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFF6B6B).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFF6B6B).withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: Color(0xFFFF6B6B), size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(_errorMessage!,
                style: const TextStyle(color: Color(0xFFFF6B6B), fontSize: 13)),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18, color: Color(0xFFFF6B6B)),
            onPressed: () => setState(() => _errorMessage = null),
          ),
        ],
      ),
    );
  }

  Widget _recordingIndicator() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFF6B6B).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFF6B6B).withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.5, end: 1.0),
            duration: const Duration(milliseconds: 800),
            builder: (context, value, child) {
              return Container(
                width: 10, height: 10,
                decoration: BoxDecoration(
                  color: Colors.red,
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: Colors.red.withValues(alpha: value * 0.5), blurRadius: 8)],
                ),
              );
            },
            onEnd: () { if (_isRecording) setState(() {}); },
          ),
          const SizedBox(width: 10),
          const Text('Listening...', style: TextStyle(color: Color(0xFFFF6B6B), fontWeight: FontWeight.w600, fontSize: 14)),
          const Spacer(),
          if (_interimText.isNotEmpty)
            Expanded(
              child: Text('...$_interimText',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Color(0xFFFF6B6B), fontSize: 12, fontStyle: FontStyle.italic)),
            ),
        ],
      ),
    );
  }

  Widget _transcriptTab() {
    if (_transcript.isEmpty && !_isRecording) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(48),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 80, height: 80,
                decoration: BoxDecoration(
                  color: const Color(0xFF16161D),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: const Color(0xFF2A2A3A)),
                ),
                child: const Icon(Icons.mic_none_rounded, size: 36, color: Color(0xFF8B8BA0)),
              ),
              const SizedBox(height: 20),
              const Text('Ready to listen', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              const Text('Tap the button below to start\nrecording your meeting',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, color: Color(0xFF8B8BA0))),
            ],
          ),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Speaker labels header + edit button
          if (_hasDiarization && _speakers.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF16161D),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF2A2A3A)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.people_outline, size: 18, color: Color(0xFF6C5CE7)),
                  const SizedBox(width: 8),
                  Text('${_speakers.length} speaker${_speakers.length > 1 ? "s" : ""} detected',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => _showSpeakerNameDialog(),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: const Color(0xFF6C5CE7).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text('Rename', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF6C5CE7))),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],

          // Diarized or plain transcript
          if (_hasDiarization && _diarizedSegments.isNotEmpty)
            ..._diarizedSegments.map((seg) {
              final speakerName = _speakers['${seg.speaker}'] ?? 'Speaker ${seg.speaker}';
              final speakerColor = _speakerColor(seg.speaker);
              final timeStr = _formatTime(seg.start);
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 36, height: 36,
                      margin: const EdgeInsets.only(right: 12),
                      decoration: BoxDecoration(
                        color: speakerColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Center(
                        child: Text(speakerName.isNotEmpty ? speakerName[0].toUpperCase() : '?',
                            style: TextStyle(color: speakerColor, fontWeight: FontWeight.w700, fontSize: 16)),
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(speakerName, style: TextStyle(color: speakerColor, fontWeight: FontWeight.w600, fontSize: 13)),
                              const SizedBox(width: 8),
                              Text(timeStr, style: const TextStyle(color: Color(0xFF8B8BA0), fontSize: 11)),
                            ],
                          ),
                          const SizedBox(height: 4),
                          SelectableText(seg.text,
                              style: const TextStyle(fontSize: 14, height: 1.5, color: Color(0xFFE8E8F0))),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            })
          else if (_transcript.isNotEmpty)
            SelectableText(_transcript.trim(),
                style: const TextStyle(fontSize: 15, height: 1.7, color: Color(0xFFE8E8F0))),

          // Audio playback button
          if (_hasAudio && _savedMeetingId != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF16161D),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF2A2A3A)),
              ),
              child: InkWell(
                onTap: _toggleAudioPlayback,
                borderRadius: BorderRadius.circular(12),
                child: Row(
                  children: [
                    Icon(
                      _isPlayingAudio ? Icons.pause_circle_filled : Icons.play_circle_filled,
                      size: 36, color: const Color(0xFF6C5CE7),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Meeting Recording', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                          const SizedBox(height: 2),
                          Text(
                            _isPlayingAudio ? 'Playing...' : 'Tap to replay',
                            style: const TextStyle(fontSize: 12, color: Color(0xFF8B8BA0)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          if (_isRecording) ...[
            if (_interimText.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(_interimText,
                  style: const TextStyle(fontSize: 15, height: 1.7, color: Color(0xFF8B8BA0), fontStyle: FontStyle.italic)),
            ],
            const SizedBox(height: 16),
            // Live preview toggle
            Center(
              child: GestureDetector(
                onTap: () {
                  setState(() => _livePreview = !_livePreview);
                  if (_isRecording) {
                    if (_livePreview) {
                      _startLivePreview();
                    } else {
                      _stopLivePreview();
                      setState(() { _interimText = '🎤 Recording... Tap stop when done'; });
                    }
                  }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF16161D),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFF2A2A3A)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _livePreview ? Icons.visibility : Icons.visibility_off,
                        size: 16, color: const Color(0xFF6C5CE7),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _livePreview ? 'Live preview ON' : 'Live preview OFF',
                        style: const TextStyle(fontSize: 12, color: Color(0xFF8B8BA0)),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF6C5CE7).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF6C5CE7))),
                    SizedBox(width: 8),
                    Text('Recording...', style: TextStyle(color: Color(0xFF6C5CE7), fontSize: 13)),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _workflowsTab() {
    if (_isAnalyzing) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(color: Color(0xFF6C5CE7)),
            const SizedBox(height: 16),
            const Text('Detecting workflows...', style: TextStyle(fontSize: 14, color: Color(0xFF8B8BA0))),
          ],
        ),
      );
    }

    if (_detectedWorkflows.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(48),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 80, height: 80,
                decoration: BoxDecoration(
                  color: const Color(0xFF16161D),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: const Color(0xFF2A2A3A)),
                ),
                child: const Icon(Icons.auto_awesome_outlined, size: 36, color: Color(0xFF8B8BA0)),
              ),
              const SizedBox(height: 20),
              const Text('No workflows detected yet',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              const Text('Record a meeting to detect\nautomatable workflows',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, color: Color(0xFF8B8BA0))),
            ],
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Row(
          children: [
            const Icon(Icons.auto_awesome, color: Color(0xFF00D2D3), size: 18),
            const SizedBox(width: 8),
            Text('Detected ${_detectedWorkflows.length} automatable workflow${_detectedWorkflows.length > 1 ? 's' : ''}',
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
          ],
        ),
        const SizedBox(height: 16),
        ..._detectedWorkflows.map((w) => _workflowCard(w)),
      ],
    );
  }

  Widget _workflowCard(Workflow w) {
    final priorityColor = switch (w.priority) {
      WorkflowPriority.high => const Color(0xFFFF6B6B),
      WorkflowPriority.medium => const Color(0xFFFDCB6E),
      WorkflowPriority.low => const Color(0xFF00D2D3),
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF16161D),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF2A2A3A)),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _showWorkflowDetail(w),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 40, height: 40,
                      decoration: BoxDecoration(
                        color: const Color(0xFF6C5CE7).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(w.icon, color: const Color(0xFF6C5CE7), size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(w.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                          const SizedBox(height: 2),
                          Text(w.category, style: const TextStyle(fontSize: 12, color: Color(0xFF8B8BA0))),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: priorityColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(w.priority.name.toUpperCase(),
                          style: TextStyle(color: priorityColor, fontSize: 10, fontWeight: FontWeight.w700)),
                    ),
                  ],
                ),
                if (w.description.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(w.description, style: const TextStyle(fontSize: 13, color: Color(0xFF8B8BA0)),
                      maxLines: 2, overflow: TextOverflow.ellipsis),
                ],
                if (w.evidence.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF6C5CE7).withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.format_quote, size: 14, color: Color(0xFF6C5CE7)),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text('"${w.evidence}"',
                              style: const TextStyle(fontSize: 12, color: Color(0xFF6C5CE7), fontStyle: FontStyle.italic),
                              maxLines: 2, overflow: TextOverflow.ellipsis),
                        ),
                      ],
                    ),
                  ),
                ],
                if (w.timeSaved != null || w.automation != null) ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      if (w.timeSaved != null) ...[
                        const Icon(Icons.schedule, size: 14, color: Color(0xFF00D2D3)),
                        const SizedBox(width: 4),
                        Text('Saves ${w.timeSaved}',
                            style: const TextStyle(color: Color(0xFF00D2D3), fontSize: 12, fontWeight: FontWeight.w500)),
                        const SizedBox(width: 12),
                      ],
                      if (w.automation != null) ...[
                        const Icon(Icons.auto_awesome, size: 14, color: Color(0xFF6C5CE7)),
                        const SizedBox(width: 4),
                        const Text('Automatable',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Color(0xFF6C5CE7))),
                      ],
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _summaryTab() {
    if (_isAnalyzing) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(color: Color(0xFF6C5CE7)),
            const SizedBox(height: 16),
            const Text('Generating summary...', style: TextStyle(fontSize: 14, color: Color(0xFF8B8BA0))),
          ],
        ),
      );
    }

    if (_summary.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(48),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 80, height: 80,
                decoration: BoxDecoration(
                  color: const Color(0xFF16161D),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: const Color(0xFF2A2A3A)),
                ),
                child: const Icon(Icons.summarize_outlined, size: 36, color: Color(0xFF8B8BA0)),
              ),
              const SizedBox(height: 20),
              const Text('AI Summary',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              const Text('After recording, AI will generate\na summary of key points',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, color: Color(0xFF8B8BA0))),
            ],
          ),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFF16161D),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF2A2A3A)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(
                    color: const Color(0xFF00D2D3).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.auto_awesome, size: 18, color: Color(0xFF00D2D3)),
                ),
                const SizedBox(width: 12),
                const Text('AI Summary', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
              ],
            ),
            const SizedBox(height: 16),
            Text(_summary, style: const TextStyle(fontSize: 15, height: 1.7)),
          ],
        ),
      ),
    );
  }

  Widget _proposalButton() {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFF6C5CE7), Color(0xFF00D2D3)]),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => Navigator.push(context, MaterialPageRoute(
              builder: (_) => ProposalScreen(meetingId: widget.meetingId ?? 'new'))),
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.description, size: 16, color: Colors.white),
                SizedBox(width: 6),
                Text('Proposal', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _followUpButton() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF16161D),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF2A2A3A)),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => Navigator.push(context, MaterialPageRoute(
              builder: (_) => FollowUpEmailScreen(meetingId: widget.meetingId ?? 'new'))),
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.email_outlined, size: 16, color: Color(0xFF00D2D3)),
                SizedBox(width: 6),
                Text('Follow-Up', style: TextStyle(color: Color(0xFF00D2D3), fontWeight: FontWeight.w600, fontSize: 13)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _bottomBar() {
    final hasTranscript = _transcript.trim().isNotEmpty;
    final isDone = !_isRecording && hasTranscript;

    if (_isRecording) {
      // Recording state - just the stop button
      return Container(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        decoration: const BoxDecoration(
          color: Color(0xFF0D0D12),
          border: Border(top: BorderSide(color: Color(0xFF2A2A3A))),
        ),
        child: SizedBox(
          width: double.infinity,
          height: 56,
          child: FilledButton.icon(
            onPressed: _toggleRecording,
            icon: const Icon(Icons.stop_rounded, size: 24),
            label: const Text('Stop', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFFF6B6B),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
          ),
        ),
      );
    }

    if (isDone) {
      // Meeting done - show Save + Copy + New
      return Container(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        decoration: const BoxDecoration(
          color: Color(0xFF0D0D12),
          border: Border(top: BorderSide(color: Color(0xFF2A2A3A))),
        ),
        child: Row(
          children: [
            // Save button
            Expanded(
              child: SizedBox(
                height: 52,
                child: FilledButton.icon(
                  onPressed: _isSaved ? null : _saveMeeting,
                  icon: Icon(_isSaved ? Icons.check_circle : Icons.save_rounded, size: 20),
                  label: Text(_isSaved ? 'Saved' : 'Save', style: const TextStyle(fontWeight: FontWeight.w600)),
                  style: FilledButton.styleFrom(
                    backgroundColor: _isSaved ? const Color(0xFF2A2A3A) : const Color(0xFF6C5CE7),
                    foregroundColor: _isSaved ? const Color(0xFF8B8BA0) : Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            // Copy button
            Expanded(
              child: SizedBox(
                height: 52,
                child: OutlinedButton.icon(
                  onPressed: _copyTranscript,
                  icon: const Icon(Icons.copy_rounded, size: 20),
                  label: const Text('Copy', style: TextStyle(fontWeight: FontWeight.w600)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF8B8BA0),
                    side: const BorderSide(color: Color(0xFF2A2A3A)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            // New meeting button
            Expanded(
              child: SizedBox(
                height: 52,
                child: OutlinedButton.icon(
                  onPressed: _resetMeeting,
                  icon: const Icon(Icons.fiber_new_rounded, size: 20),
                  label: const Text('New', style: TextStyle(fontWeight: FontWeight.w600)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF00D2D3),
                    side: const BorderSide(color: Color(0xFF2A2A3A)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    // Default - start button
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      decoration: const BoxDecoration(
        color: Color(0xFF0D0D12),
        border: Border(top: BorderSide(color: Color(0xFF2A2A3A))),
      ),
      child: SizedBox(
        width: double.infinity,
        height: 56,
        child: FilledButton.icon(
          onPressed: _toggleRecording,
          icon: const Icon(Icons.mic_rounded, size: 24),
          label: const Text('Start', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF6C5CE7),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
        ),
      ),
    );
  }

  /// Save meeting to local storage
  Future<String?> _saveMeetingToBackend(String transcript, String? serverMeetingId) async {
    if (transcript.trim().isEmpty) return null;
    final auth = ref.read(authProvider);
    if (!auth.isAuthenticated) return null;

    try {
      final body = <String, dynamic>{
        'title': _generateTitle(),
        'transcript': transcript.trim(),
      };
      if (_audioFilename != null) {
        body['audio_filename'] = _audioFilename;
        body['audio_duration'] = _audioDuration;
      }
      final response = await http.post(
        Uri.parse('${auth.apiUrl}/api/meetings'),
        headers: auth.authHeaders,
        body: jsonEncode(body),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['id'] as String?;
      }
    } catch (_) {}
    return null;
  }

  Future<void> _saveMeeting() async {
    if (_transcript.trim().isEmpty) return;

    final id = _savedMeetingId ?? DateTime.now().millisecondsSinceEpoch.toString();
    final meeting = Meeting(
      id: id,
      title: _generateTitle(),
      date: DateTime.now(),
      summary: _summary,
      workflowCount: _detectedWorkflows.length,
      durationMinutes: 0, // TODO: track actual duration
      transcript: _transcript.trim(),
    );

    await MeetingStorage.save(meeting, ref.read(authProvider));
    setState(() {
      _isSaved = true;
      _savedMeetingId = id;
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Meeting saved!'),
          backgroundColor: Color(0xFF6C5CE7),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  /// Copy transcript to clipboard
  void _copyTranscript() {
    if (_transcript.trim().isEmpty) return;

    final text = StringBuffer();
    text.writeln('=== Clozr Meeting Transcript ===');
    text.writeln('Date: ${DateTime.now().month}/${DateTime.now().day}/${DateTime.now().year}');
    if (_summary.isNotEmpty) text.writeln('Summary: $_summary');
    text.writeln();
    text.writeln(_transcript.trim());
    if (_detectedWorkflows.isNotEmpty) {
      text.writeln();
      text.writeln('--- Detected Workflows ---');
      for (final w in _detectedWorkflows) {
        text.writeln('• ${w.name}: ${w.description}');
      }
    }

    Clipboard.setData(ClipboardData(text: text.toString()));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Transcript copied to clipboard!'),
        backgroundColor: Color(0xFF00D2D3),
        duration: Duration(seconds: 2),
      ),
    );
  }

  /// Reset for a new meeting
  void _resetMeeting() {
    setState(() {
      _transcript = '';
      _interimText = '';
      _summary = '';
      _detectedWorkflows = [];
      _isSaved = false;
      _savedMeetingId = null;
      _errorMessage = null;
      _isRecording = false;
      _isAnalyzing = false;
      _diarizedSegments = [];
      _speakers = {};
      _hasDiarization = false;
    });
  }

  /// Generate a title from the first line of transcript
  String _generateTitle() {
    if (_transcript.trim().isEmpty) return 'Untitled Meeting';
    final firstLine = _transcript.trim().split('\n').first;
    if (firstLine.length > 50) return '${firstLine.substring(0, 47)}...';
    return firstLine;
  }

  Color _speakerColor(int speakerIndex) {
    const colors = [
      Color(0xFF6C5CE7), Color(0xFF00D2D3), Color(0xFFFF6B6B),
      Color(0xFFFDCB6E), Color(0xFF55EFC4), Color(0xFFFD79A8),
      Color(0xFF74B9FF), Color(0xFFA29BFE),
    ];
    return colors[speakerIndex % colors.length];
  }

  String _formatTime(double seconds) {
    final mins = (seconds / 60).floor();
    final secs = (seconds % 60).floor();
    return '$mins:${secs.toString().padLeft(2, '0')}';
  }

  void _showSpeakerNameDialog() {
    final controllers = <String, TextEditingController>{};
    for (final entry in _speakers.entries) {
      controllers[entry.key] = TextEditingController(text: entry.value);
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF16161D),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          left: 24, right: 24, top: 24,
          bottom: MediaQuery.of(context).viewInsets.bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(
                color: const Color(0xFF2A2A3A), borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 20),
            const Text('Name Speakers', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            const Text('Assign names to detected speakers for better transcript readability.',
                style: TextStyle(fontSize: 13, color: Color(0xFF8B8BA0))),
            const SizedBox(height: 20),
            ...controllers.entries.map((entry) {
              final speakerIdx = entry.key;
              final controller = entry.value;
              final color = _speakerColor(int.parse(speakerIdx));
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  children: [
                    Container(
                      width: 36, height: 36,
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Center(
                        child: Text(controller.text.isNotEmpty ? controller.text[0].toUpperCase() : speakerIdx,
                            style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 16)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: controller,
                        style: const TextStyle(fontSize: 15, color: Color(0xFFE8E8F0)),
                        decoration: InputDecoration(
                          hintText: 'Speaker $speakerIdx',
                          hintStyle: const TextStyle(color: Color(0xFF8B8BA0)),
                          filled: true,
                          fillColor: const Color(0xFF0D0D12),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(color: Color(0xFF2A2A3A)),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(color: Color(0xFF2A2A3A)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(color: color),
                          ),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        ),
                        onChanged: (_) {
                          // Update avatar initial dynamically
                          (context as Element).markNeedsBuild();
                        },
                      ),
                    ),
                  ],
                ),
              );
            }),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton.icon(
                onPressed: () async {
                  // Build new speaker map
                  final newSpeakers = <String, String>{};
                  for (final entry in controllers.entries) {
                    final name = entry.value.text.trim();
                    newSpeakers[entry.key] = name.isEmpty ? 'Speaker ${entry.key}' : name;
                  }
                  Navigator.pop(context);

                  // Save to backend
                  await _saveSpeakerNames(newSpeakers);
                },
                icon: const Icon(Icons.check),
                label: const Text('Save Names', style: TextStyle(fontWeight: FontWeight.w600)),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF6C5CE7),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _saveSpeakerNames(Map<String, String> newSpeakers) async {
    final auth = ref.read(authProvider);
    if (!auth.isAuthenticated || _savedMeetingId == null) return;

    try {
      final response = await http.put(
        Uri.parse('${auth.apiUrl}/api/meetings/$_savedMeetingId/speakers'),
        headers: {...auth.authHeaders, 'Content-Type': 'application/json'},
        body: jsonEncode({'speakers': newSpeakers}),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _speakers = newSpeakers;
          if (data['transcript'] != null) {
            _transcript = data['transcript'];
          }
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Speaker names saved!'),
              backgroundColor: Color(0xFF6C5CE7),
              duration: Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (_) {
      // Still update locally even if server save fails
      setState(() { _speakers = newSpeakers; });
    }
  }

  void _showWorkflowDetail(Workflow w) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF16161D),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.65,
        minChildSize: 0.5,
        maxChildSize: 0.85,
        expand: false,
        builder: (context, controller) => SingleChildScrollView(
          controller: controller,
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(
                  color: const Color(0xFF2A2A3A), borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 24),
              Row(
                children: [
                  Container(
                    width: 52, height: 52,
                    decoration: BoxDecoration(
                      color: const Color(0xFF6C5CE7).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(w.icon, color: const Color(0xFF6C5CE7), size: 26),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(w.name, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(w.description, style: const TextStyle(fontSize: 15, height: 1.6)),
              if (w.evidence.isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF6C5CE7).withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.format_quote, size: 16, color: Color(0xFF6C5CE7)),
                      const SizedBox(width: 6),
                      Expanded(child: Text('"${w.evidence}"',
                          style: const TextStyle(fontSize: 13, color: Color(0xFF6C5CE7), fontStyle: FontStyle.italic))),
                    ],
                  ),
                ),
              ],
              if (w.automation != null) ...[
                const SizedBox(height: 20),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF6C5CE7).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFF6C5CE7).withValues(alpha: 0.3)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.auto_awesome, size: 16, color: Color(0xFF6C5CE7)),
                          const SizedBox(width: 8),
                          const Text('How we automate this',
                              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(w.automation!, style: const TextStyle(fontSize: 13, height: 1.5)),
                    ],
                  ),
                ),
              ],
              if (w.timeSaved != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF00D2D3).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.schedule, size: 18, color: Color(0xFF00D2D3)),
                      const SizedBox(width: 8),
                      const Text('Time saved:', style: TextStyle(fontSize: 14)),
                      const SizedBox(width: 4),
                      Text(w.timeSaved!, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: Color(0xFF00D2D3))),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    Navigator.push(context, MaterialPageRoute(
                        builder: (_) => ProposalScreen(meetingId: widget.meetingId ?? 'new')));
                  },
                  icon: const Icon(Icons.description),
                  label: const Text('Add to Proposal', style: TextStyle(fontWeight: FontWeight.w600)),
                  style: FilledButton.styleFrom(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    Navigator.push(context, MaterialPageRoute(
                        builder: (_) => FollowUpEmailScreen(meetingId: widget.meetingId ?? 'new')));
                  },
                  icon: const Icon(Icons.email_outlined, color: Color(0xFF00D2D3)),
                  label: const Text('Draft Follow-Up Email', style: TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF00D2D3))),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFF2A2A3A)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}