import 'package:flutter/material.dart';
import '../models/meeting.dart';

class TranscriptWidget extends StatelessWidget {
  final String transcript;
  final bool isRecording;
  final List<DiarizedSegment>? diarizedSegments;
  final Map<String, String>? speakers;

  const TranscriptWidget({
    super.key,
    required this.transcript,
    required this.isRecording,
    this.diarizedSegments,
    this.speakers,
  });

  @override
  Widget build(BuildContext context) {
    if (transcript.isEmpty && !isRecording) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.mic_none_rounded, size: 64,
                color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 16),
            const Text('Tap Start Recording to begin',
              style: TextStyle(fontSize: 16)),
            const SizedBox(height: 8),
            const Text('Jarvis will transcribe your meeting in real-time',
              style: TextStyle(fontSize: 13)),
          ],
        ),
      );
    }

    // If we have diarized segments, show speaker-labeled view
    if (diarizedSegments != null && diarizedSegments!.isNotEmpty && speakers != null) {
      return _diarizedTranscriptView(context);
    }

    // Fallback: plain transcript
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: SelectableText(
        transcript.isEmpty ? 'Listening...' : transcript,
        style: const TextStyle(fontSize: 15, height: 1.6),
      ),
    );
  }

  Widget _diarizedTranscriptView(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: diarizedSegments!.length,
      itemBuilder: (context, index) {
        final seg = diarizedSegments![index];
        final speakerName = speakers?['${seg.speaker}'] ?? 'Speaker ${seg.speaker}';
        final isEven = seg.speaker % 2 == 0;
        final speakerColor = _speakerColor(seg.speaker);
        final timeStr = _formatTime(seg.start);

        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Speaker avatar
              Container(
                width: 36,
                height: 36,
                margin: const EdgeInsets.only(right: 12),
                decoration: BoxDecoration(
                  color: speakerColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Center(
                  child: Text(
                    speakerName.isNotEmpty ? speakerName[0].toUpperCase() : '?',
                    style: TextStyle(
                      color: speakerColor,
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
              // Content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          speakerName,
                          style: TextStyle(
                            color: speakerColor,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          timeStr,
                          style: const TextStyle(
                            color: Color(0xFF8B8BA0),
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    SelectableText(
                      seg.text,
                      style: const TextStyle(
                        fontSize: 14,
                        height: 1.5,
                        color: Color(0xFFE8E8F0),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Color _speakerColor(int speakerIndex) {
    const colors = [
      Color(0xFF6C5CE7), // Purple
      Color(0xFF00D2D3), // Teal
      Color(0xFFFF6B6B), // Red
      Color(0xFFFDCB6E), // Yellow
      Color(0xFF55EFC4), // Green
      Color(0xFFFD79A8), // Pink
      Color(0xFF74B9FF), // Blue
      Color(0xFFA29BFE), // Lavender
    ];
    return colors[speakerIndex % colors.length];
  }

  String _formatTime(double seconds) {
    final mins = (seconds / 60).floor();
    final secs = (seconds % 60).floor();
    return '${mins}:${secs.toString().padLeft(2, '0')}';
  }
}