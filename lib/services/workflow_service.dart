import 'package:flutter/material.dart';
import '../models/workflow.dart';
import '../models/service_catalog.dart';
import '../services/catalog_storage.dart';
import '../services/auth_service.dart';
import '../services/llm_service.dart';

/// Workflow Detection Service — now via backend proxy (A1 fix)
/// Uses authenticated LLM endpoint instead of direct API calls
class WorkflowService {
  final AuthService _auth;
  final LLMService _llm;

  WorkflowService(this._auth) : _llm = LLMService(_auth);

  /// Detect automatable workflows from transcript
  /// Uses the user's custom service catalog (falls back to BrandBoost defaults)
  Future<List<Workflow>> detectWorkflows(String transcript) async {
    if (!_auth.isAuthenticated) {
      return [];
    }

    try {
      final results = await _llm.detectWorkflows(transcript);

      // Load catalog for matching
      final catalogItems = await CatalogStorage.load(_auth);
      final List<Workflow> workflows = [];

      for (final item in results) {
        final key = item['catalog_key'] as String?;
        final template = catalogItems.where((c) => c.id == key).firstOrNull;
        if (template != null) {
          workflows.add(Workflow(
            name: template.name,
            category: template.category,
            icon: _iconForName(template.icon),
            description: template.description,
            evidence: item['evidence'] as String? ?? '',
            priority: _priorityFromString(item['priority'] as String? ?? 'medium'),
            automation: template.automation,
            timeSaved: template.timeSaved,
            monthlyCost: template.monthlyCost,
          ));
        }
      }

      // Also add new workflows not in catalog
      final newWorkflows = results
          .where((item) => item['catalog_key'] == null && item.containsKey('name'))
          .map((item) => Workflow(
                name: item['name'] as String? ?? 'Custom Workflow',
                category: item['category'] as String? ?? 'Custom',
                icon: Icons.auto_awesome,
                description: item['description'] as String? ?? '',
                evidence: item['evidence'] as String? ?? '',
                priority: _priorityFromString(item['priority'] as String? ?? 'medium'),
              ))
          .toList();

      return [...workflows, ...newWorkflows];
    } catch (_) {
      // Silently fail — return empty list
      return [];
    }
  }

  WorkflowPriority _priorityFromString(String priority) {
    return switch (priority.toLowerCase()) {
      'high' => WorkflowPriority.high,
      'medium' => WorkflowPriority.medium,
      _ => WorkflowPriority.low,
    };
  }

  IconData _iconForName(String name) {
    return switch (name) {
      'star' => Icons.star,
      'phone_android' => Icons.phone_android,
      'search' => Icons.search,
      'inventory' => Icons.inventory_2_outlined,
      'bar_chart' => Icons.bar_chart,
      'email' => Icons.email_outlined,
      'calendar_today' => Icons.calendar_today,
      'track_changes' => Icons.track_changes,
      'shopping_cart' => Icons.shopping_cart_outlined,
      'people' => Icons.people_outline,
      'support_agent' => Icons.support_agent,
      'trending_up' => Icons.trending_up,
      'cloud_sync' => Icons.cloud_sync,
      _ => Icons.auto_awesome,
    };
  }
}

class WorkflowTemplate {
  final String name;
  final String category;
  final IconData icon;
  final String description;
  final String automation;
  final String timeSaved;
  final String monthlyCost;

  const WorkflowTemplate({
    required this.name,
    required this.category,
    required this.icon,
    required this.description,
    required this.automation,
    required this.timeSaved,
    required this.monthlyCost,
  });
}