import 'dart:convert';

class DiarizedSegment {
  final int speaker;
  final double start;
  final double end;
  final String text;

  const DiarizedSegment({
    required this.speaker,
    required this.start,
    required this.end,
    required this.text,
  });

  factory DiarizedSegment.fromJson(Map<String, dynamic> json) => DiarizedSegment(
    speaker: (json['speaker'] as num?)?.toInt() ?? 0,
    start: (json['start'] as num?)?.toDouble() ?? 0.0,
    end: (json['end'] as num?)?.toDouble() ?? 0.0,
    text: json['text'] as String? ?? '',
  );

  Map<String, dynamic> toJson() => {
    'speaker': speaker,
    'start': start,
    'end': end,
    'text': text,
  };
}

class Meeting {
  final String id;
  final String? title;
  final DateTime date;
  final String? summary;
  final int workflowCount;
  final int durationMinutes;
  // New fields for saved data
  final String? transcript;
  final String? proposalJson;
  final bool hasAudio;
  final double audioDuration;
  // Diarization fields
  final Map<String, String> speakers; // {"0": "Ron", "1": "Client"}
  final List<DiarizedSegment> diarizedSegments;
  final bool hasDiarization;

  const Meeting({
    required this.id,
    this.title,
    required this.date,
    this.summary,
    this.workflowCount = 0,
    this.durationMinutes = 0,
    this.transcript,
    this.proposalJson,
    this.hasAudio = false,
    this.audioDuration = 0.0,
    this.speakers = const {},
    this.diarizedSegments = const [],
    this.hasDiarization = false,
  });

  String get dateFormatted {
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inDays == 0) return 'Today';
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) return '${diff.inDays} days ago';
    return '${date.month}/${date.day}/${date.year}';
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'date': date.toIso8601String(),
    'summary': summary,
    'workflowCount': workflowCount,
    'durationMinutes': durationMinutes,
    'transcript': transcript,
    'proposalJson': proposalJson,
  };

  factory Meeting.fromJson(Map<String, dynamic> json) => Meeting(
    id: json['id'] as String,
    title: json['title'] as String?,
    date: DateTime.parse(json['created_at'] as String? ?? json['date'] as String),
    summary: json['summary'] as String?,
    workflowCount: (json['workflowCount'] as num?)?.toInt() ?? (json['workflow_count'] as num?)?.toInt() ?? 0,
    durationMinutes: (json['durationMinutes'] as num?)?.toInt() ?? (json['duration_minutes'] as num?)?.toInt() ?? 0,
    transcript: json['transcript'] as String?,
    proposalJson: json['proposalJson'] as String?,
    hasAudio: json['has_audio'] as bool? ?? false,
    audioDuration: (json['audio_duration'] as num?)?.toDouble() ?? 0.0,
    speakers: (json['speakers'] as Map<String, dynamic>?)?.map((k, v) => MapEntry(k, v.toString())) ?? {},
    diarizedSegments: (json['diarized_segments'] as List?)?.map((s) => DiarizedSegment.fromJson(s as Map<String, dynamic>)).toList() ?? [],
    hasDiarization: json['has_diarization'] as bool? ?? false,
  );
}