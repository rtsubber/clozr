import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../services/auth_service.dart';

/// Public proposal view — accessible without auth via shareable link
class ProposalViewScreen extends StatefulWidget {
  final String proposalId;

  const ProposalViewScreen({super.key, required this.proposalId});

  @override
  State<ProposalViewScreen> createState() => _ProposalViewScreenState();
}

class _ProposalViewScreenState extends State<ProposalViewScreen> {
  bool _isLoading = true;
  Map<String, dynamic>? _proposal;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadProposal();
  }

  Future<void> _loadProposal() async {
    try {
      final response = await http.get(
        Uri.parse('${AuthService.basePath}/api/proposals/${widget.proposalId}'),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _proposal = data;
          _isLoading = false;
        });

        // Track view
        _trackView();
      } else if (response.statusCode == 404) {
        setState(() {
          _error = 'Proposal not found';
          _isLoading = false;
        });
      } else {
        setState(() {
          _error = 'Failed to load proposal';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Connection error. Please try again.';
        _isLoading = false;
      });
    }
  }

  Future<void> _trackView() async {
    try {
      await http.post(
        Uri.parse('${AuthService.basePath}/api/proposals/${widget.proposalId}/viewed'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'device_type': 'mobile'}),  // Flutter = mobile default
      );
    } catch (_) {
      // Don't fail on tracking error
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D12),
      body: SafeArea(child: _buildBody()),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: Color(0xFF6C5CE7)),
            SizedBox(height: 16),
            Text('Loading proposal...', style: TextStyle(color: Color(0xFF8B8BA0))),
          ],
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Color(0xFFFF6B6B)),
              const SizedBox(height: 16),
              Text(_error!, style: const TextStyle(fontSize: 16, color: Color(0xFFE8E8F0))),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _loadProposal,
                icon: const Icon(Icons.refresh),
                label: const Text('Try Again'),
                style: FilledButton.styleFrom(backgroundColor: const Color(0xFF6C5CE7)),
              ),
            ],
          ),
        ),
      );
    }

    final p = _proposal!;
    final painPoints = (p['pain_points'] as List?)?.map((x) => x.toString()).toList() ?? [];
    final solutions = (p['solutions'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final nextSteps = (p['next_steps'] as List?)?.map((x) => x.toString()).toList() ?? [];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          const Row(
            children: [
              Icon(Icons.handshake_outlined, color: Color(0xFF6C5CE7), size: 32),
              SizedBox(width: 12),
              Text('The Clozr', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: 8),
          Text('Proposal for ${p['client_name'] ?? 'Client'}',
              style: const TextStyle(fontSize: 14, color: Color(0xFF8B8BA0))),
          const Divider(color: Color(0xFF2A2A3A), height: 32),

          // Executive Summary
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFF16161D),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF2A2A3A)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(children: [
                  Icon(Icons.description_outlined, color: Color(0xFF6C5CE7), size: 22),
                  SizedBox(width: 10),
                  Text('Executive Summary', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                ]),
                const SizedBox(height: 12),
                Text(p['executive_summary'] ?? '', style: const TextStyle(fontSize: 15, height: 1.7, color: Color(0xFFC8C8D8))),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Pain Points
          if (painPoints.isNotEmpty) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF16161D),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFF2A2A3A)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(children: [
                    Icon(Icons.warning_amber_rounded, color: Color(0xFFFF6B6B), size: 22),
                    SizedBox(width: 10),
                    Text('Current Challenges', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                  ]),
                  const SizedBox(height: 12),
                  ...painPoints.map((pp) => Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF6B6B).withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(children: [
                      const Icon(Icons.circle, size: 6, color: Color(0xFFFF6B6B)),
                      const SizedBox(width: 10),
                      Expanded(child: Text(pp, style: const TextStyle(fontSize: 14))),
                    ]),
                  )),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Solutions
          if (solutions.isNotEmpty) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF16161D),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFF2A2A3A)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(children: [
                    Icon(Icons.auto_awesome, color: Color(0xFF6C5CE7), size: 22),
                    SizedBox(width: 10),
                    Text('Recommended Solutions', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                  ]),
                  const SizedBox(height: 16),
                  ...solutions.map((s) => Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF6C5CE7).withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFF6C5CE7).withValues(alpha: 0.2)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Expanded(child: Text(s['service'] ?? '', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15))),
                          if ((s['monthly_cost'] ?? '').isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: const Color(0xFF00D2D3).withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(s['monthly_cost'], style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: Color(0xFF00D2D3))),
                            ),
                        ]),
                        const SizedBox(height: 6),
                        Text(s['description'] ?? '', style: const TextStyle(fontSize: 13, color: Color(0xFF8B8BA0), height: 1.5)),
                        if ((s['time_saved'] ?? '').isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Row(children: [
                            const Icon(Icons.schedule, size: 14, color: Color(0xFF00D2D3)),
                            const SizedBox(width: 4),
                            Text('Saves ${s['time_saved']}', style: const TextStyle(fontSize: 13, color: Color(0xFF00D2D3))),
                          ]),
                        ],
                      ],
                    ),
                  )),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          // ROI Stats
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF6C5CE7), Color(0xFF4834D4)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _statColumn('Time Saved', p['total_time_saved'] ?? ''),
                _statColumn('Cost', p['estimated_monthly_cost'] ?? ''),
                _statColumn('ROI', p['roi_percentage'] ?? ''),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Next Steps
          if (nextSteps.isNotEmpty) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF16161D),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFF2A2A3A)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(children: [
                    Icon(Icons.checklist_rtl_rounded, color: Color(0xFF6C5CE7), size: 22),
                    SizedBox(width: 10),
                    Text('Next Steps', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                  ]),
                  const SizedBox(height: 12),
                  ...nextSteps.asMap().entries.map((e) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(children: [
                      Container(
                        width: 28, height: 28,
                        decoration: BoxDecoration(
                          color: const Color(0xFF6C5CE7).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Center(child: Text('${e.key + 1}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: Color(0xFF6C5CE7)))),
                      ),
                      const SizedBox(width: 12),
                      Expanded(child: Text(e.value, style: const TextStyle(fontSize: 14))),
                    ]),
                  )),
                ],
              ),
            ),
          ],

          const SizedBox(height: 32),
          const Center(
            child: Text(
              'Powered by The Clozr',
              style: TextStyle(fontSize: 12, color: Color(0xFF8B8BA0)),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _statColumn(String label, String value) {
    return Column(
      children: [
        Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white)),
        const SizedBox(height: 4),
        Text(label, style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.7))),
      ],
    );
  }
}