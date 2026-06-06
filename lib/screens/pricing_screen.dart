import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import '../main.dart';
import '../services/auth_service.dart';

class PricingScreen extends ConsumerStatefulWidget {
  const PricingScreen({super.key});

  @override
  ConsumerState<PricingScreen> createState() => _PricingScreenState();
}

class _PricingScreenState extends ConsumerState<PricingScreen> {
  bool _isAnnual = true; // Default to annual (save 20%)
  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D12),
      appBar: AppBar(
        backgroundColor: const Color(0xFF16161D),
        title: const Text('Choose Your Plan', style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const SizedBox(height: 16),

            // Tagline
            Text(
              'Turn every meeting into your next deal.',
              style: TextStyle(
                color: Colors.white.withOpacity(0.7),
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'No spam. No data training. Cancel anytime.',
              style: TextStyle(
                color: const Color(0xFF6C5CE7).withOpacity(0.8),
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 24),

            // Monthly/Annual toggle
            _buildBillingToggle(),
            const SizedBox(height: 24),

            // Pricing cards
            LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth > 900) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: _buildFreeCard()),
                      const SizedBox(width: 12),
                      Expanded(child: _buildProCard()),
                      const SizedBox(width: 12),
                      Expanded(child: _buildBusinessCard()),
                      const SizedBox(width: 12),
                      Expanded(child: _buildSelfHostedCard()),
                    ],
                  );
                }
                return Column(
                  children: [
                    _buildFreeCard(),
                    const SizedBox(height: 16),
                    _buildProCard(),
                    const SizedBox(height: 16),
                    _buildBusinessCard(),
                    const SizedBox(height: 16),
                    _buildSelfHostedCard(),
                  ],
                );
              },
            ),

            const SizedBox(height: 32),

            // Trust bar
            _buildTrustBar(),

            const SizedBox(height: 24),

            // VS competitors
            _buildComparisonTable(),

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildBillingToggle() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onTap: () => setState(() => _isAnnual = false),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
              decoration: BoxDecoration(
                color: !_isAnnual ? const Color(0xFF6C5CE7) : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text('Monthly',
                style: TextStyle(color: !_isAnnual ? Colors.white : Colors.white54),
              ),
            ),
          ),
          GestureDetector(
            onTap: () => setState(() => _isAnnual = true),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
              decoration: BoxDecoration(
                color: _isAnnual ? const Color(0xFF6C5CE7) : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Annual',
                    style: TextStyle(color: _isAnnual ? Colors.white : Colors.white54),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00D68F),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text('Save 20%',
                      style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFreeCard() {
    return _buildPlanCard(
      name: 'Free',
      price: '\$0',
      period: 'forever',
      description: 'Try it out. The proposal hook is free.',
      isPopular: false,
      features: const [
        '5 meetings/month',
        'Up to 60 min/meeting',
        '2 proposals/month',
        '3 follow-up emails/month',
        'AI summary + action items',
        'Speaker diarization',
        '7-day storage',
        'Web + Android + PWA',
        'No data training ever',
      ],
      onTap: () => _handleSubscribe('free'),
      buttonLabel: 'Get Started',
      borderColor: const Color(0xFF2A2A3A),
    );
  }

  Widget _buildProCard() {
    final price = _isAnnual ? '\$15' : '\$19';
    final period = _isAnnual ? '/mo (billed yearly)' : '/month';

    return _buildPlanCard(
      name: 'Pro',
      price: price,
      period: period,
      description: 'For freelancers, consultants, and sales reps.',
      isPopular: true,
      features: const [
        'Unlimited meetings',
        'Unlimited transcription',
        'Unlimited proposals',
        'Unlimited follow-up emails',
        '10 custom templates',
        'Deepgram diarization',
        'Zapier + Google Drive',
        '1-year storage',
        'Priority support',
      ],
      onTap: () => _handleSubscribe(_isAnnual ? 'pro_annual' : 'pro_monthly'),
      buttonLabel: 'Start Free Trial',
      borderColor: const Color(0xFF6C5CE7),
    );
  }

  Widget _buildBusinessCard() {
    final price = _isAnnual ? '\$32' : '\$39';
    final period = _isAnnual ? '/mo (billed yearly)' : '/month';

    return _buildPlanCard(
      name: 'Business',
      price: price,
      period: period,
      description: 'For teams and agencies. 5 seats included.',
      isPopular: false,
      features: const [
        'Everything in Pro',
        '5 seats included (+\$7/extra)',
        'Team template library',
        'Custom branding on docs',
        'HubSpot + Salesforce + Slack',
        '3-year storage',
        'Deal pipeline view',
        'Admin controls',
      ],
      onTap: () => _handleSubscribe(_isAnnual ? 'business_annual' : 'business_monthly'),
      buttonLabel: 'Start Free Trial',
      borderColor: const Color(0xFF00D68F),
    );
  }

  Widget _buildSelfHostedCard() {
    final price = _isAnnual ? '\$65' : '\$79';
    final period = _isAnnual ? '/mo (billed yearly)' : '/month';

    return _buildPlanCard(
      name: 'Self-Hosted',
      price: price,
      period: period,
      description: 'Your infrastructure. Your data. Zero trust required.',
      isPopular: false,
      features: const [
        'Everything in Business',
        'Up to 20 seats',
        'Runs on your servers',
        'No data ever leaves your infra',
        'Docker deployment + docs',
        'Local LLM support (Ollama)',
        'White-label available (\$299)',
        'Dedicated support',
      ],
      onTap: () => _handleSubscribe(_isAnnual ? 'selfhosted_annual' : 'selfhosted_monthly'),
      buttonLabel: 'Contact Us',
      borderColor: const Color(0xFFFF6B6B),
    );
  }

  Widget _buildPlanCard({
    required String name,
    required String price,
    required String period,
    required String description,
    required bool isPopular,
    required List<String> features,
    required VoidCallback onTap,
    required String buttonLabel,
    required Color borderColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF16161D),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isPopular ? borderColor : const Color(0xFF2A2A3A), width: isPopular ? 2 : 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isPopular)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: borderColor,
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text('MOST POPULAR',
                style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
              ),
            ),
          if (isPopular) const SizedBox(height: 8),
          Text(name, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(description, style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 13)),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(price, style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.bold)),
              const SizedBox(width: 4),
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(period, style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 13)),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: onTap,
              style: ElevatedButton.styleFrom(
                backgroundColor: isPopular ? borderColor : const Color(0xFF2A2A3A),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: Text(buttonLabel, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            ),
          ),
          const SizedBox(height: 16),
          ...features.map((f) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('✓', style: TextStyle(color: Color(0xFF00D68F), fontSize: 14)),
                const SizedBox(width: 8),
                Expanded(child: Text(f, style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 13))),
              ],
            ),
          )),
        ],
      ),
    );
  }

  Widget _buildTrustBar() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
      decoration: BoxDecoration(
        color: const Color(0xFF16161D),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF2A2A3A)),
      ),
      child: const Wrap(
        alignment: WrapAlignment.center,
        spacing: 24,
        runSpacing: 8,
        children: [
          _TrustBadge(icon: '🔒', text: 'No data training ever'),
          _TrustBadge(icon: '🚫', text: 'No spam sharing'),
          _TrustBadge(icon: '🌍', text: 'Android + Web + PWA'),
          _TrustBadge(icon: '🔐', text: 'Self-host available'),
        ],
      ),
    );
  }

  Widget _buildComparisonTable() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF16161D),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF2A2A3A)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('How We Compare', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          _buildComparisonRow('Feature', ['Clozr', 'Granola', 'Fireflies', 'Otter', 'Fathom'], header: true),
          _buildComparisonRow('Proposals', ['✅', '❌', '❌', '❌', '❌']),
          _buildComparisonRow('Android', ['✅', '❌', '✅', '✅', '❌']),
          _buildComparisonRow('Self-host', ['✅', '❌', '❌', '❌', '❌']),
          _buildComparisonRow('No data training', ['✅', '❌', '❌', '❌', '✅']),
          _buildComparisonRow('Pro price', ['\$19', '\$14*', '\$10', '\$8', '\$16']),
          const SizedBox(height: 8),
          Text('*Granola \$14 = notes only. Clozr \$19 = notes + proposals + docs.',
            style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _buildComparisonRow(String label, List<String> values, {bool header = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(label,
              style: TextStyle(
                color: header ? const Color(0xFF6C5CE7) : Colors.white70,
                fontWeight: header ? FontWeight.bold : FontWeight.normal,
                fontSize: 13,
              ),
            ),
          ),
          ...values.map((v) => Expanded(
            child: Text(v,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: header ? Colors.white : (v == '✅' ? const Color(0xFF00D68F) : (v == '❌' ? const Color(0xFFFF6B6B) : Colors.white60)),
                fontSize: 13,
                fontWeight: header ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          )),
        ],
      ),
    );
  }

  Future<void> _handleSubscribe(String planKey) async {
    if (planKey == 'free') {
      // Just redirect to register
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Free plan — just create an account!'), backgroundColor: Color(0xFF00D68F)),
      );
      return;
    }

    final auth = ref.read(authProvider);
    if (!auth.isAuthenticated) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please sign in first'), backgroundColor: Color(0xFF8B8BA0)),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      // Call our backend to create a Stripe checkout session
      final response = await http.post(
        Uri.parse('${auth.apiUrl}/api/payments/checkout'),
        headers: {...auth.authHeaders, 'Content-Type': 'application/json'},
        body: jsonEncode({
          'price_key': planKey,
          'account_id': auth.accountId,
          'email': auth.accountId ?? '',
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        // Redirect to Stripe Checkout
        if (data['url'] != null) {
          // Launch Stripe Checkout in browser
          final uri = Uri.parse(data['url'] as String);
          if (await canLaunchUrl(uri)) {
            await launchUrl(uri, mode: LaunchMode.externalApplication);
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Could not open checkout page'), backgroundColor: const Color(0xFF8B8BA0)),
            );
          }
        }
      } else {
        throw Exception('Checkout failed: ${response.body}');
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: const Color(0xFFFF6B6B)),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }
}

class _TrustBadge extends StatelessWidget {
  final String icon;
  final String text;
  const _TrustBadge({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(icon, style: const TextStyle(fontSize: 16)),
        const SizedBox(width: 6),
        Text(text, style: const TextStyle(color: Colors.white70, fontSize: 13)),
      ],
    );
  }
}