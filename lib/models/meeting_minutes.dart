class MeetingMinutes {
  final String id;
  final String? meetingId;
  final String meetingTitle;
  final String meetingType;
  final List<Attendee> attendees;
  final String summary;
  final List<KeyDecision> keyDecisions;
  final List<ActionItem> actionItems;
  final List<DiscussionTopic> discussionTopics;
  final List<String> parkingLot;
  final List<String> openQuestions;
  final List<String> riskFlags;
  final String nextMeeting;
  final String status;
  final DateTime createdAt;

  const MeetingMinutes({
    required this.id,
    this.meetingId,
    required this.meetingTitle,
    this.meetingType = 'General',
    this.attendees = const [],
    this.summary = '',
    this.keyDecisions = const [],
    this.actionItems = const [],
    this.discussionTopics = const [],
    this.parkingLot = const [],
    this.openQuestions = const [],
    this.riskFlags = const [],
    this.nextMeeting = '',
    this.status = 'draft',
    required this.createdAt,
  });

  factory MeetingMinutes.fromJson(Map<String, dynamic> json) {
    return MeetingMinutes(
      id: json['id']?.toString() ?? DateTime.now().millisecondsSinceEpoch.toString(),
      meetingId: json['meeting_id']?.toString(),
      meetingTitle: json['meeting_title'] ?? json['title'] ?? 'Untitled Meeting',
      meetingType: json['meeting_type'] ?? 'General',
      attendees: (json['attendees'] as List?)
              ?.map((e) => Attendee.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      summary: json['summary'] ?? '',
      keyDecisions: (json['key_decisions'] as List?)
              ?.map((e) => KeyDecision.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      actionItems: (json['action_items'] as List?)
              ?.map((e) => ActionItem.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      discussionTopics: (json['discussion_topics'] as List?)
              ?.map((e) => DiscussionTopic.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      parkingLot: (json['parking_lot'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      openQuestions: (json['open_questions'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      riskFlags: (json['risk_flags'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      nextMeeting: json['next_meeting'] ?? '',
      status: json['status'] ?? 'draft',
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'meeting_id': meetingId,
      'meeting_title': meetingTitle,
      'meeting_type': meetingType,
      'attendees': attendees.map((e) => {'name': e.name, 'role': e.role}).toList(),
      'summary': summary,
      'key_decisions': keyDecisions
          .map((e) => {
                'decision': e.decision,
                'rationale': e.rationale,
                'decided_by': e.decidedBy,
              })
          .toList(),
      'action_items': actionItems
          .map((e) => {
                'id': e.id,
                'task': e.task,
                'owner': e.owner,
                'due_date': e.dueDate,
                'priority': e.priority,
                'status': e.status,
              })
          .toList(),
      'discussion_topics': discussionTopics
          .map((e) => {
                'topic': e.topic,
                'points': e.points,
                'outcome': e.outcome,
              })
          .toList(),
      'parking_lot': parkingLot,
      'open_questions': openQuestions,
      'risk_flags': riskFlags,
      'next_meeting': nextMeeting,
      'status': status,
      'created_at': createdAt.toIso8601String(),
    };
  }
}

class Attendee {
  final String name;
  final String role;

  const Attendee({required this.name, this.role = ''});

  factory Attendee.fromJson(Map<String, dynamic> json) =>
      Attendee(name: json['name'] ?? '', role: json['role'] ?? '');
}

class KeyDecision {
  final String decision;
  final String rationale;
  final String decidedBy;

  const KeyDecision({
    required this.decision,
    this.rationale = '',
    this.decidedBy = '',
  });

  factory KeyDecision.fromJson(Map<String, dynamic> json) => KeyDecision(
        decision: json['decision'] ?? '',
        rationale: json['rationale'] ?? '',
        decidedBy: json['decided_by'] ?? json['decidedBy'] ?? '',
      );
}

class ActionItem {
  final String id;
  final String task;
  final String owner;
  final String dueDate;
  final String priority;
  final String status;

  const ActionItem({
    required this.id,
    required this.task,
    this.owner = '',
    this.dueDate = '',
    this.priority = 'medium',
    this.status = 'open',
  });

  factory ActionItem.fromJson(Map<String, dynamic> json) => ActionItem(
        id: json['id'] ?? '',
        task: json['task'] ?? '',
        owner: json['owner'] ?? '',
        dueDate: json['due_date'] ?? json['dueDate'] ?? '',
        priority: json['priority'] ?? 'medium',
        status: json['status'] ?? 'open',
      );
}

class DiscussionTopic {
  final String topic;
  final List<String> points;
  final String outcome;

  const DiscussionTopic({
    required this.topic,
    this.points = const [],
    this.outcome = '',
  });

  factory DiscussionTopic.fromJson(Map<String, dynamic> json) => DiscussionTopic(
        topic: json['topic'] ?? '',
        points: (json['points'] as List?)
                ?.map((e) => e.toString())
                .toList() ??
            [],
        outcome: json['outcome'] ?? '',
      );
}