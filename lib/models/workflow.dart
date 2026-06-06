import 'package:flutter/material.dart';

enum WorkflowPriority { high, medium, low }

class Workflow {
  final String name;
  final String category;
  final IconData icon;
  final String description;
  final String evidence; // What was said that triggered detection
  final WorkflowPriority priority;
  final String? automation; // How we'd automate it
  final String? timeSaved;
  final String? monthlyCost;

  const Workflow({
    required this.name,
    required this.category,
    this.icon = Icons.auto_awesome,
    required this.description,
    this.evidence = '',
    this.priority = WorkflowPriority.medium,
    this.automation,
    this.timeSaved,
    this.monthlyCost,
  });

  Map<String, dynamic> toMap() => {
    'name': name,
    'category': category,
    'description': description,
    'evidence': evidence,
    'priority': priority.name,
    'automation': automation,
    'time_saved': timeSaved,
    'monthly_cost': monthlyCost,
  };
}