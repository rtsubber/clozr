import 'package:flutter/material.dart';
import '../models/workflow.dart';

class WorkflowCard extends StatelessWidget {
  final Workflow workflow;
  final VoidCallback onTap;

  const WorkflowCard({super.key, required this.workflow, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final priorityColor = switch (workflow.priority) {
      WorkflowPriority.high => Colors.red,
      WorkflowPriority.medium => Colors.orange,
      WorkflowPriority.low => Colors.green,
    };

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(workflow.icon, 
                      color: Theme.of(context).colorScheme.primary, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(workflow.name, 
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                        const SizedBox(height: 2),
                        Text(workflow.category,
                          style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ),
                  ),
                  // Priority badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: priorityColor.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      workflow.priority.name.toUpperCase(),
                      style: TextStyle(color: priorityColor, fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(workflow.description, 
                style: Theme.of(context).textTheme.bodyMedium,
                maxLines: 2, overflow: TextOverflow.ellipsis),
              if (workflow.timeSaved != null || workflow.automation != null) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    if (workflow.timeSaved != null) ...[
                      Icon(Icons.schedule, size: 14, color: Theme.of(context).colorScheme.primary),
                      const SizedBox(width: 4),
                      Text('Saves ${workflow.timeSaved}',
                        style: TextStyle(color: Theme.of(context).colorScheme.primary, fontSize: 13)),
                      const SizedBox(width: 12),
                    ],
                    if (workflow.automation != null) ...[
                      Icon(Icons.auto_awesome, size: 14, color: Theme.of(context).colorScheme.primary),
                      const SizedBox(width: 4),
                      const Text('Automatable', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                    ],
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}