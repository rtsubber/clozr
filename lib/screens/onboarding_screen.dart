import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../main.dart';
import '../models/service_catalog.dart';
import '../services/catalog_storage.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  int _step = 0; // 0=welcome, 1=import, 2=review, 3=done
  bool _isImporting = false;
  String _importStatus = '';
  List<ServiceItem> _importedServices = [];
  final _urlController = TextEditingController();

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D12),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 500),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_step == 0) _buildWelcome(),
                  if (_step == 1) _buildImport(),
                  if (_step == 2) _buildReview(),
                  if (_step == 3) _buildDone(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildWelcome() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(Icons.auto_awesome, size: 56, color: Color(0xFF6C5CE7)),
        const SizedBox(height: 20),
        const Text(
          'Welcome to The Clozr!',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: Color(0xFFE8E8F0)),
        ),
        const SizedBox(height: 8),
        const Text(
          'Let\'s set up your service catalog so Clozr can create proposals tailored to your business.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, color: Color(0xFF8B8BA0)),
        ),
        const SizedBox(height: 32),
        _optionCard(
          icon: Icons.auto_awesome,
          title: 'Use default catalog',
          subtitle: 'Start with 8 pre-built service templates for agencies',
          onTap: () => _useDefaults(),
        ),
        const SizedBox(height: 12),
        _optionCard(
          icon: Icons.language,
          title: 'Import from your website',
          subtitle: 'We\'ll scan your site and extract your services & pricing',
          onTap: () => setState(() => _step = 1),
        ),
        const SizedBox(height: 12),
        _optionCard(
          icon: Icons.upload_file,
          title: 'Upload a PDF or DOCX',
          subtitle: 'Import your service menu, pricing sheet, or capabilities doc',
          onTap: () => _importPdf(),
        ),
        const SizedBox(height: 12),
        _optionCard(
          icon: Icons.edit_note,
          title: 'Start from scratch',
          subtitle: 'Add services manually one at a time',
          onTap: () => setState(() => _step = 2),
        ),
      ],
    );
  }

  Widget _optionCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Material(
      color: const Color(0xFF16161D),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFF2A2A3A)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF6C5CE7).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: const Color(0xFF6C5CE7), size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFFE8E8F0))),
                    const SizedBox(height: 2),
                    Text(subtitle, style: const TextStyle(fontSize: 13, color: Color(0xFF8B8BA0))),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Color(0xFF8B8BA0)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildImport() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(Icons.language, size: 48, color: Color(0xFF6C5CE7)),
        const SizedBox(height: 20),
        const Text(
          'Import from Website',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: Color(0xFFE8E8F0)),
        ),
        const SizedBox(height: 8),
        const Text(
          'Enter your business website URL and we\'ll automatically extract your services and pricing.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, color: Color(0xFF8B8BA0)),
        ),
        const SizedBox(height: 24),
        TextField(
          controller: _urlController,
          keyboardType: TextInputType.url,
          autocorrect: false,
          style: const TextStyle(color: Color(0xFFE8E8F0)),
          decoration: InputDecoration(
            labelText: 'Website URL',
            labelStyle: const TextStyle(color: Color(0xFF8B8BA0)),
            hintText: 'https://yourbusiness.com',
            hintStyle: const TextStyle(color: Color(0xFF4A4A5A)),
            prefixIcon: const Icon(Icons.language, color: Color(0xFF6C5CE7)),
            filled: true,
            fillColor: const Color(0xFF16161D),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFF2A2A3A)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFF2A2A3A)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFF6C5CE7)),
            ),
          ),
        ),
        const SizedBox(height: 24),
        if (_importStatus.isNotEmpty) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _isImporting
                ? const Color(0xFF6C5CE7).withValues(alpha: 0.1)
                : const Color(0xFF00D2D3).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                if (_isImporting)
                  const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF6C5CE7)))
                else
                  const Icon(Icons.check_circle, color: Color(0xFF00D2D3), size: 16),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _importStatus,
                    style: TextStyle(
                      fontSize: 14,
                      color: _isImporting ? const Color(0xFFE8E8F0) : const Color(0xFF00D2D3),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
        SizedBox(
          width: double.infinity,
          height: 56,
          child: FilledButton.icon(
            onPressed: _isImporting ? null : _importFromUrl,
            icon: _isImporting
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.download_rounded, size: 22),
            label: Text(
              _isImporting ? 'Analyzing...' : 'Import Services',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF6C5CE7),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
          ),
        ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: () => setState(() => _step = 0),
          child: const Text('← Back', style: TextStyle(color: Color(0xFF8B8BA0))),
        ),
      ],
    );
  }

  Widget _buildReview() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(
          _importedServices.isEmpty ? Icons.edit_note : Icons.fact_check,
          size: 48,
          color: const Color(0xFF6C5CE7),
        ),
        const SizedBox(height: 20),
        Text(
          _importedServices.isEmpty ? 'Your Service Catalog' : 'Review Imported Services',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: Color(0xFFE8E8F0)),
        ),
        const SizedBox(height: 8),
        Text(
          _importedServices.isEmpty
            ? 'Add your services below. These will power your proposals.'
            : '${_importedServices.length} services ready. You can add more or continue.',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 14, color: Color(0xFF8B8BA0)),
        ),
        const SizedBox(height: 24),

        // Services list or empty state
        if (_importedServices.isNotEmpty) ...[
          ..._importedServices.map((svc) => Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF16161D),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFF2A2A3A)),
            ),
            child: Row(
              children: [
                Icon(_iconForName(svc.icon), color: const Color(0xFF6C5CE7), size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(svc.name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFFE8E8F0))),
                      Text(svc.category, style: const TextStyle(fontSize: 12, color: Color(0xFF8B8BA0))),
                    ],
                  ),
                ),
                Text(svc.monthlyCost, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF00D2D3))),
              ],
            ),
          )),
        ] else ...[
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFF16161D),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFF2A2A3A)),
            ),
            child: const Column(
              children: [
                Icon(Icons.add_business, size: 40, color: Color(0xFF8B8BA0)),
                SizedBox(height: 12),
                Text('No services yet', style: TextStyle(fontSize: 16, color: Color(0xFF8B8BA0))),
                SizedBox(height: 4),
                Text('You can add services later in Settings', style: TextStyle(fontSize: 13, color: Color(0xFF6A6A7A))),
              ],
            ),
          ),
        ],
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          height: 56,
          child: FilledButton.icon(
            onPressed: _finishOnboarding,
            icon: const Icon(Icons.check_rounded, size: 22),
            label: Text(
              _importedServices.isEmpty ? 'Continue with Defaults' : 'Looks Good — Continue',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF6C5CE7),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
          ),
        ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: () => setState(() => _step = 0),
          child: const Text('← Start Over', style: TextStyle(color: Color(0xFF8B8BA0))),
        ),
      ],
    );
  }

  Widget _buildDone() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(Icons.celebration, size: 56, color: Color(0xFF00D2D3)),
        const SizedBox(height: 20),
        const Text(
          'You\'re All Set! 🎉',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: Color(0xFFE8E8F0)),
        ),
        const SizedBox(height: 8),
        Text(
          _importedServices.isEmpty
            ? 'Default catalog loaded. You can customize it anytime.'
            : '${_importedServices.length} services imported and ready.',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 14, color: Color(0xFF8B8BA0)),
        ),
        const SizedBox(height: 32),
        SizedBox(
          width: double.infinity,
          height: 56,
          child: FilledButton.icon(
            onPressed: () => context.go('/'),
            icon: const Icon(Icons.mic_rounded, size: 22),
            label: const Text('Start Your First Meeting', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF6C5CE7),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
          ),
        ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: () => context.go('/catalog'),
          child: const Text('Edit Catalog →', style: TextStyle(color: Color(0xFF8B8BA0), fontSize: 14)),
        ),
      ],
    );
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
      'auto_awesome' => Icons.auto_awesome,
      'shopping_cart' => Icons.shopping_cart_outlined,
      'people' => Icons.people_outline,
      'support_agent' => Icons.support_agent,
      'trending_up' => Icons.trending_up,
      'cloud_sync' => Icons.cloud_sync,
      'business_center' => Icons.business_center,
      _ => Icons.auto_awesome,
    };
  }

  Future<void> _useDefaults() async {
    setState(() {
      _isImporting = true;
      _importStatus = 'Loading default catalog...';
    });

    final auth = ref.read(authProvider);
    final defaults = DefaultCatalog.brandboost();

    int created = 0;
    for (final item in defaults) {
      final success = await CatalogStorage.addItem(item, auth);
      if (success) created++;
    }

    if (!mounted) return;
    setState(() {
      _importedServices = defaults;
      _isImporting = false;
      _importStatus = '$created services loaded!';
      _step = 2;
    });
  }

  Future<void> _importFromUrl() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) return;

    setState(() {
      _isImporting = true;
      _importStatus = 'Fetching and analyzing...';
    });

    try {
      final auth = ref.read(authProvider);
      final response = await http.post(
        Uri.parse('${auth.apiUrl}/api/catalog/import-url'),
        headers: auth.authHeaders,
        body: jsonEncode({'url': url}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final services = (data['services'] as List?)?.map((s) => ServiceItem(
          id: s['id'] ?? '',
          name: s['name'] ?? '',
          category: s['category'] ?? 'General',
          description: s['description'] ?? '',
          monthlyCost: s['price'] ?? s['monthly_cost'] ?? 'Custom',
          icon: s['icon'] ?? 'auto_awesome',
        )).toList() ?? [];

        if (!mounted) return;
        setState(() {
          _importedServices = services;
          _isImporting = false;
          _importStatus = 'Imported ${data['imported']} services!';
          _step = 2;
        });
      } else {
        final error = jsonDecode(response.body);
        if (!mounted) return;
        setState(() {
          _importStatus = 'Error: ${error['detail'] ?? 'Import failed'}';
          _isImporting = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _importStatus = 'Error: $e';
        _isImporting = false;
      });
    }
  }

  Future<void> _importPdf() async {
    // PDF import uses the existing import sheet
    // For onboarding, redirect to catalog screen with import
    if (!mounted) return;
    context.go('/catalog');
  }

  void _finishOnboarding() {
    setState(() => _step = 3);
  }
}