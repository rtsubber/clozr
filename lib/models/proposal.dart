class Proposal {
  final String id;
  final String meetingId;
  final String clientName;
  final DateTime date;
  final String executiveSummary;
  final List<PainPoint> painPoints;
  final List<ProposedSolution> solutions;
  final List<String> scopeDeliverables;
  final List<String> scopeExcluded;
  final String? timeline;
  final String totalTimeSaved;
  final String estimatedMonthlyCost;
  final String roiPercentage;
  final List<String> nextSteps;
  final List<String> openQuestions;
  final String? closingLine;

  const Proposal({
    required this.id,
    required this.meetingId,
    required this.clientName,
    required this.date,
    required this.executiveSummary,
    required this.painPoints,
    required this.solutions,
    this.scopeDeliverables = const [],
    this.scopeExcluded = const [],
    this.timeline,
    required this.totalTimeSaved,
    required this.estimatedMonthlyCost,
    required this.roiPercentage,
    required this.nextSteps,
    this.openQuestions = const [],
    this.closingLine,
  });
}

class PainPoint {
  final String description;
  final String? evidence;

  const PainPoint({required this.description, this.evidence});
}

class ProposedSolution {
  final String service;
  final String description;
  final String timeSaved;
  final String monthlyCost;

  const ProposedSolution({
    required this.service,
    required this.description,
    required this.timeSaved,
    required this.monthlyCost,
  });
}