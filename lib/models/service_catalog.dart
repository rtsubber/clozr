import 'package:flutter/material.dart';

/// A single service offering in a user's catalog
class ServiceItem {
  final String id;
  final String name;
  final String category;
  final String description;
  final String automation;
  final String timeSaved;
  final String monthlyCost;
  final String icon;

  const ServiceItem({
    required this.id,
    required this.name,
    required this.category,
    required this.description,
    this.automation = '',
    this.timeSaved = '',
    this.monthlyCost = '',
    this.icon = 'auto_awesome',
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'category': category,
    'description': description,
    'automation': automation,
    'timeSaved': timeSaved,
    'monthlyCost': monthlyCost,
    'icon': icon,
  };

  factory ServiceItem.fromJson(Map<String, dynamic> json) => ServiceItem(
    id: json['id'] as String? ?? '',
    name: json['name'] as String? ?? '',
    category: json['category'] as String? ?? 'General',
    description: json['description'] as String? ?? '',
    automation: json['automation'] as String? ?? '',
    timeSaved: json['timeSaved'] as String? ?? '',
    monthlyCost: json['monthlyCost'] as String? ?? '',
    icon: json['icon'] as String? ?? 'auto_awesome',
  );

  /// Convert to the format the LLM workflow detector expects
  String toCatalogString() {
    final parts = ['- $id: $name ($category)'];
    if (timeSaved.isNotEmpty) parts[0] += ' — saves $timeSaved';
    return parts.join('\n');
  }
}

/// Default BrandBoost catalog — loaded on first launch
class DefaultCatalog {
  static List<ServiceItem> brandboost() => [
    ServiceItem(
      id: 'review_monitoring',
      name: 'Review Monitoring & Response',
      category: 'Reputation Management',
      description: 'Monitor Google/Yelp/Facebook reviews daily and auto-respond',
      automation: 'Local-Eye + Agent Monitor watches for new reviews, generates AI responses for approval, posts after confirmation',
      timeSaved: '45 min/day',
      monthlyCost: '\$299',
      icon: 'star',
    ),
    ServiceItem(
      id: 'social_posting',
      name: 'Social Media Auto-Posting',
      category: 'Social Media',
      description: 'Automated social media content creation and scheduling',
      automation: 'AI generates captions from product data, schedules posts across Facebook/TikTok/YouTube',
      timeSaved: '30 min/day',
      monthlyCost: '\$199',
      icon: 'phone_android',
    ),
    ServiceItem(
      id: 'seo_monitoring',
      name: 'SEO & Competitor Monitoring',
      category: 'SEO & Marketing',
      description: 'Track competitor changes and SEO performance weekly',
      automation: 'SEO Agent monitors rankings, competitor activity, and content opportunities automatically',
      timeSaved: '2 hrs/week',
      monthlyCost: '\$249',
      icon: 'search',
    ),
    ServiceItem(
      id: 'inventory_sync',
      name: 'Inventory & Order Sync',
      category: 'E-Commerce',
      description: 'Automatically sync inventory between suppliers and store',
      automation: 'Scheduled sync between Zendrop/CJ Dropshipping and Shopify, with stock alerts',
      timeSaved: '30 min/day',
      monthlyCost: '\$149',
      icon: 'inventory',
    ),
    ServiceItem(
      id: 'daily_reporting',
      name: 'Automated Daily Reports',
      category: 'Reporting',
      description: 'Generate and send daily performance reports',
      automation: 'n8n workflow collects data from all sources, generates formatted report, emails at scheduled time',
      timeSaved: '20 min/day',
      monthlyCost: '\$149',
      icon: 'bar_chart',
    ),
    ServiceItem(
      id: 'email_templating',
      name: 'Smart Email Responses',
      category: 'Communication',
      description: 'Auto-draft responses to common customer emails',
      automation: 'AI categorizes incoming emails, drafts responses using business context, queues for approval',
      timeSaved: '25 min/day',
      monthlyCost: '\$149',
      icon: 'email',
    ),
    ServiceItem(
      id: 'appointment_booking',
      name: 'Appointment Booking Automation',
      category: 'Scheduling',
      description: 'Auto-schedule and confirm appointments via phone or web',
      automation: 'Maya AI answers calls, books appointments, sends confirmations via SMS/email',
      timeSaved: '1 hr/day',
      monthlyCost: '\$399',
      icon: 'calendar_today',
    ),
    ServiceItem(
      id: 'lead_followup',
      name: 'Lead Follow-Up Sequences',
      category: 'Sales',
      description: 'Automated follow-up emails and calls for new leads',
      automation: 'New leads trigger personalized email sequence + Maya AI follow-up calls',
      timeSaved: '45 min/day',
      monthlyCost: '\$299',
      icon: 'track_changes',
    ),
  ];
}