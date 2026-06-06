import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import '../models/proposal.dart';
import '../models/meeting.dart';
import '../services/auth_service.dart';
import '../services/llm_service.dart';
import '../services/meeting_storage.dart';
import '../main.dart';

class ProposalScreen extends ConsumerStatefulWidget {
  final String meetingId;
  final Map<String, dynamic>? proposalData;
  
  const ProposalScreen({super.key, required this.meetingId, this.proposalData});

  @override
  ConsumerState<ProposalScreen> createState() => _ProposalScreenState();
}

class _ProposalScreenState extends ConsumerState<ProposalScreen> {
  bool _isGenerating = true;
  bool _isSharing = false;
  String? _shareUrl;
  Proposal? _proposal;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.proposalData != null) {
      _proposal = _parseProposalData(widget.proposalData!);
      _isGenerating = false;
    } else {
      _generateProposal();
    }
  }

  Proposal _parseProposalData(Map<String, dynamic> d) {
    return Proposal(
      id: d['id']?.toString() ?? '1',
      meetingId: widget.meetingId,
      clientName: d['client_name'] ?? 'Client',
      date: DateTime.now(),
      executiveSummary: d['executive_summary'] ?? '',
      painPoints: (d['current_pain_points'] as List?)?.map((p) {
        if (p is Map<String, dynamic>) {
          return PainPoint(description: p['description']?.toString() ?? '', evidence: p['evidence']?.toString());
        }
        return PainPoint(description: p.toString());
      }).toList() ?? [],
      solutions: (d['proposed_solutions'] as List?)?.map((s) {
        if (s is Map<String, dynamic>) {
          return ProposedSolution(
            service: s['service']?.toString() ?? '',
            description: s['description']?.toString() ?? '',
            timeSaved: s['time_saved']?.toString() ?? '',
            monthlyCost: s['monthly_cost']?.toString() ?? '',
          );
        }
        return const ProposedSolution(service: '', description: '', timeSaved: '', monthlyCost: '');
      }).toList() ?? [],
      scopeDeliverables: (d['scope_deliverables'] as List?)?.map((e) => e.toString()).toList() ?? [],
      scopeExcluded: (d['scope_excluded'] as List?)?.map((e) => e.toString()).toList() ?? [],
      timeline: d['timeline']?.toString(),
      totalTimeSaved: d['total_time_saved']?.toString() ?? '',
      estimatedMonthlyCost: d['estimated_monthly_cost']?.toString() ?? '',
      roiPercentage: d['roi_percentage']?.toString() ?? '',
      nextSteps: (d['next_steps'] as List?)?.map((s) => s.toString()).toList() ?? [],
      openQuestions: (d['open_questions'] as List?)?.map((q) => q.toString()).toList() ?? [],
      closingLine: d['closing_line']?.toString(),
    );
  }

  Future<void> _generateProposal() async {
    try {
      final auth = ref.read(authProvider);
      final llm = LLMService(auth);
      
      final meetings = await MeetingStorage.loadAll(auth);
      final meeting = meetings.firstWhere(
        (m) => m.id == widget.meetingId, 
        orElse: () => Meeting(id: '', title: 'Unknown', date: DateTime.now()),
      );
      final transcript = meeting.transcript ?? '';
      
      if (transcript.isEmpty) {
        setState(() {
          _isGenerating = false;
          _proposal = Proposal(
            id: '1', meetingId: widget.meetingId, clientName: 'No transcript available',
            date: DateTime.now(),
            executiveSummary: 'Record a meeting first to generate a proposal. The AI needs transcript data to analyze.',
            painPoints: const [], solutions: const [],
            totalTimeSaved: '', estimatedMonthlyCost: '', roiPercentage: '',
            nextSteps: const ['Record a meeting', 'Generate a proposal'],
          );
        });
        return;
      }
      
      final result = await llm.generateProposal(transcript: transcript);
      setState(() {
        _isGenerating = false;
        _proposal = _parseProposalData(result);
      });
    } catch (e) {
      setState(() {
        _isGenerating = false;
        _proposal = Proposal(
          id: '1', meetingId: widget.meetingId, clientName: 'Generation failed',
          date: DateTime.now(),
          executiveSummary: 'Could not generate proposal: $e',
          painPoints: const [], solutions: const [],
          totalTimeSaved: '', estimatedMonthlyCost: '', roiPercentage: '',
          nextSteps: const ['Try again'],
        );
      });
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
    if (_isGenerating) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: Color(0xFF6C5CE7)),
            SizedBox(height: 16),
            Text('Crafting your proposal...', style: TextStyle(color: Color(0xFF8B8BA0))),
            SizedBox(height: 8),
            Text('Extracting client needs → Building proposal', style: TextStyle(color: Color(0xFF6C5CE7), fontSize: 13)),
          ],
        ),
      );
    }
    if (_error != null) return Center(child: Text(_error!, style: const TextStyle(color: Color(0xFFFF6B6B))));
    if (_proposal != null) return _buildProposal();
    return const Center(child: Text('No proposal data'));
  }

  Widget _buildProposal() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ──
          Row(children: [
            IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.arrow_back_ios_new, size: 20),
              style: IconButton.styleFrom(foregroundColor: const Color(0xFF8B8BA0))),
            const Expanded(child: Text('Proposal', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700))),
            IconButton(onPressed: _shareProposal, icon: const Icon(Icons.share_rounded, size: 22),
              style: IconButton.styleFrom(foregroundColor: const Color(0xFF6C5CE7)), tooltip: 'Share'),
            IconButton(onPressed: _copyProposal, icon: const Icon(Icons.copy_rounded, size: 22),
              style: IconButton.styleFrom(foregroundColor: const Color(0xFF8B8BA0)), tooltip: 'Copy'),
          ]),

          // ── Share banner ──
          if (_shareUrl != null) ...[
            const SizedBox(height: 12),
            Container(width: double.infinity, padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: const Color(0xFF00D2D3).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF00D2D3).withValues(alpha: 0.3))),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Row(children: [Icon(Icons.check_circle, color: Color(0xFF00D2D3), size: 18), SizedBox(width: 8),
                  Text('Proposal shared!', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14))]),
                const SizedBox(height: 8),
                Text(_shareUrl!, style: const TextStyle(fontSize: 12, color: Color(0xFF8B8BA0))),
                const SizedBox(height: 4),
                const Text('You\'ll be notified when they view it', style: TextStyle(fontSize: 12, color: Color(0xFF8B8BA0))),
              ])),
          ],

          const SizedBox(height: 20),

          // ── Client name + date ──
          if (_proposal!.clientName.isNotEmpty && _proposal!.clientName != 'Client') ...[
            Text('Prepared for', style: const TextStyle(fontSize: 12, color: Color(0xFF8B8BA0), letterSpacing: 1)),
            const SizedBox(height: 4),
            Text(_proposal!.clientName, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
            const SizedBox(height: 16),
          ],

          // ── Executive Summary ──
          _sectionCard(Icons.description_outlined, const Color(0xFF6C5CE7), 'What We Heard',
            Text(_proposal!.executiveSummary, style: const TextStyle(fontSize: 15, height: 1.7, color: Color(0xFFC8C8D8)))),

          const SizedBox(height: 16),

          // ── Pain Points (with evidence) ──
          if (_proposal!.painPoints.isNotEmpty) ...[
            _sectionCard(Icons.warning_amber_rounded, const Color(0xFFFF6B6B), 'Current Challenges',
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                ..._proposal!.painPoints.map((p) => Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: const Color(0xFFFF6B6B).withValues(alpha: 0.06), borderRadius: BorderRadius.circular(10)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      const Icon(Icons.circle, size: 6, color: Color(0xFFFF6B6B)),
                      const SizedBox(width: 10),
                      Expanded(child: Text(p.description, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600))),
                    ]),
                    if (p.evidence != null && p.evidence!.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Padding(padding: const EdgeInsets.only(left: 16),
                        child: Text('"${p.evidence}"', style: const TextStyle(fontSize: 12, color: Color(0xFF8B8BA0), fontStyle: FontStyle.italic))),
                    ],
                  ]),
                )),
              ])),
            const SizedBox(height: 16),
          ],

          // ── Solutions ──
          if (_proposal!.solutions.isNotEmpty) ...[
            _sectionCard(Icons.auto_awesome, const Color(0xFF6C5CE7), 'Recommended Solutions',
              Column(children: [
                ..._proposal!.solutions.map((s) => Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: const Color(0xFF6C5CE7).withValues(alpha: 0.06), borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFF6C5CE7).withValues(alpha: 0.15))),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(child: Text(s.service, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15))),
                      if (s.monthlyCost.isNotEmpty)
                        Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(color: const Color(0xFF00D2D3).withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
                          child: Text(s.monthlyCost, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: Color(0xFF00D2D3)))),
                    ]),
                    const SizedBox(height: 6),
                    Text(s.description, style: const TextStyle(fontSize: 13, color: Color(0xFF8B8BA0), height: 1.5)),
                    if (s.timeSaved.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Row(children: [
                        const Icon(Icons.schedule, size: 14, color: Color(0xFF00D2D3)),
                        const SizedBox(width: 4),
                        Text('Saves ${s.timeSaved}', style: const TextStyle(fontSize: 13, color: Color(0xFF00D2D3))),
                      ]),
                    ],
                  ]),
                )),
              ])),
            const SizedBox(height: 16),
          ],

          // ── Scope: Deliverables ──
          if (_proposal!.scopeDeliverables.isNotEmpty) ...[
            _sectionCard(Icons.check_circle_outline, const Color(0xFF00E676), 'Scope of Work',
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                ..._proposal!.scopeDeliverables.asMap().entries.map((e) => Padding(
                  padding: const EdgeInsets.only(bottom: 8, left: 4),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Container(width: 22, height: 22, margin: const EdgeInsets.only(right: 10, top: 1),
                      decoration: BoxDecoration(color: const Color(0xFF00E676).withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)),
                      child: Center(child: Text('${e.key + 1}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 11, color: Color(0xFF00E676))))),
                    Expanded(child: Text(e.value, style: const TextStyle(fontSize: 14, height: 1.5))),
                  ]),
                )),
              ])),
            const SizedBox(height: 16),
          ],

          // ── Scope: Exclusions ──
          if (_proposal!.scopeExcluded.isNotEmpty) ...[
            _sectionCard(Icons.block, const Color(0xFF8B8BA0), 'Not Included',
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                ..._proposal!.scopeExcluded.map((e) => Padding(
                  padding: const EdgeInsets.only(bottom: 6, left: 4),
                  child: Row(children: [
                    const Icon(Icons.remove_circle_outline, size: 14, color: Color(0xFF8B8BA0)),
                    const SizedBox(width: 8),
                    Expanded(child: Text(e, style: const TextStyle(fontSize: 13, color: Color(0xFF8B8BA0)))),
                  ]),
                )),
              ])),
            const SizedBox(height: 16),
          ],

          // ── Timeline ──
          if (_proposal!.timeline != null && _proposal!.timeline!.isNotEmpty) ...[
            _sectionCard(Icons.calendar_today, const Color(0xFF6C5CE7), 'Timeline',
              Text(_proposal!.timeline!, style: const TextStyle(fontSize: 14, height: 1.7, color: Color(0xFFC8C8D8)))),
            const SizedBox(height: 16),
          ],

          // ── ROI Stats ──
          Container(padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFF6C5CE7), Color(0xFF4834D4)],
              begin: Alignment.topLeft, end: Alignment.bottomRight), borderRadius: BorderRadius.circular(16)),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
              _statColumn('Time Saved', _proposal!.totalTimeSaved),
              _statColumn('Monthly Cost', _proposal!.estimatedMonthlyCost),
              _statColumn('ROI', _proposal!.roiPercentage),
            ])),
          const SizedBox(height: 16),

          // ── Next Steps ──
          if (_proposal!.nextSteps.isNotEmpty) ...[
            _sectionCard(Icons.checklist_rtl_rounded, const Color(0xFF6C5CE7), 'Next Steps',
              Column(children: [
                ..._proposal!.nextSteps.asMap().entries.map((e) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(children: [
                    Container(width: 28, height: 28,
                      decoration: BoxDecoration(color: const Color(0xFF6C5CE7).withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
                      child: Center(child: Text('${e.key + 1}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: Color(0xFF6C5CE7))))),
                    const SizedBox(width: 12),
                    Expanded(child: Text(e.value, style: const TextStyle(fontSize: 14))),
                  ]),
                )),
              ])),
            const SizedBox(height: 16),
          ],

          // ── Open Questions (needs manual input) ──
          if (_proposal!.openQuestions.isNotEmpty) ...[
            Container(width: double.infinity, padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: const Color(0xFFFF6B6B).withValues(alpha: 0.06), borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFFF6B6B).withValues(alpha: 0.2))),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Row(children: [
                  Icon(Icons.edit_note, color: Color(0xFFFF6B6B), size: 22),
                  SizedBox(width: 10),
                  Text('Review Before Sending', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                ]),
                const SizedBox(height: 8),
                const Text('These items need your input:', style: TextStyle(fontSize: 13, color: Color(0xFF8B8BA0))),
                const SizedBox(height: 10),
                ..._proposal!.openQuestions.map((q) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Icon(Icons.arrow_right, size: 16, color: Color(0xFFFF6B6B)),
                    const SizedBox(width: 6),
                    Expanded(child: Text(q, style: const TextStyle(fontSize: 13))),
                  ]),
                )),
              ])),
            const SizedBox(height: 16),
          ],

          // ── Closing line ──
          if (_proposal!.closingLine != null && _proposal!.closingLine!.isNotEmpty) ...[
            Container(width: double.infinity, padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: const Color(0xFF00D2D3).withValues(alpha: 0.06), borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF00D2D3).withValues(alpha: 0.2))),
              child: Row(children: [
                const Icon(Icons.format_quote, color: Color(0xFF00D2D3), size: 18),
                const SizedBox(width: 10),
                Expanded(child: Text(_proposal!.closingLine!, style: const TextStyle(fontSize: 14, fontStyle: FontStyle.italic, color: Color(0xFFC8C8D8)))),
              ])),
            const SizedBox(height: 24),
          ],

          // ── Share CTA ──
          SizedBox(width: double.infinity, height: 56,
            child: FilledButton.icon(
              onPressed: _isSharing ? null : _shareProposal,
              icon: _isSharing
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.send_rounded, size: 22),
              label: Text(_isSharing ? 'Creating link...' : 'Share Proposal',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFF6C5CE7),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
            )),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _sectionCard(IconData icon, Color color, String title, Widget content) {
    return Container(width: double.infinity, padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: const Color(0xFF16161D), borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF2A2A3A))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [Icon(icon, color: color, size: 22), const SizedBox(width: 10),
          Text(title, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: color))]),
        const SizedBox(height: 12),
        content,
      ]));
  }

  Widget _statColumn(String label, String value) {
    return Column(children: [
      Text(value.isEmpty ? '—' : value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white)),
      const SizedBox(height: 4),
      Text(label, style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.7))),
    ]);
  }

  /// Share proposal — uploads to API and gets a shareable link
  Future<void> _shareProposal() async {
    if (_proposal == null || _isSharing) return;
    setState(() => _isSharing = true);

    try {
      final proposalData = {
        'client_name': _proposal!.clientName,
        'executive_summary': _proposal!.executiveSummary,
        'current_pain_points': _proposal!.painPoints.map((p) => p.description).toList(),
        'proposed_solutions': _proposal!.solutions.map((s) => {
          'service': s.service, 'description': s.description,
          'time_saved': s.timeSaved, 'monthly_cost': s.monthlyCost,
        }).toList(),
        'scope_deliverables': _proposal!.scopeDeliverables,
        'scope_excluded': _proposal!.scopeExcluded,
        'total_time_saved': _proposal!.totalTimeSaved,
        'estimated_monthly_cost': _proposal!.estimatedMonthlyCost,
        'roi_percentage': _proposal!.roiPercentage,
        'next_steps': _proposal!.nextSteps,
        'open_questions': _proposal!.openQuestions,
        if (_proposal!.closingLine != null) 'closing_line': _proposal!.closingLine,
      };

      final auth = ref.read(authProvider);
      if (!auth.isAuthenticated) throw Exception('Not authenticated. Please log in.');

      final response = await http.post(
        Uri.parse('${auth.apiUrl}/api/proposals'),
        headers: auth.authHeaders,
        body: jsonEncode(proposalData),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final sharePath = data['share_url'] as String;
        final shareUrl = '${AuthService.basePath}$sharePath';
        setState(() { _shareUrl = shareUrl; _isSharing = false; });
        await Clipboard.setData(ClipboardData(text: shareUrl));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Link copied! Share: $shareUrl'),
            backgroundColor: const Color(0xFF6C5CE7), duration: const Duration(seconds: 4)));
        }
      } else {
        throw Exception('Failed to create share link');
      }
    } catch (e) {
      setState(() => _isSharing = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error sharing: $e'), backgroundColor: const Color(0xFFFF6B6B)));
      }
    }
  }

  /// Copy proposal text to clipboard
  void _copyProposal() {
    if (_proposal == null) return;
    final text = StringBuffer();
    text.writeln('=== Proposal for ${_proposal!.clientName} ===');
    text.writeln();
    text.writeln(_proposal!.executiveSummary);
    text.writeln();
    if (_proposal!.painPoints.isNotEmpty) {
      text.writeln('Challenges:');
      for (final p in _proposal!.painPoints) {
        text.writeln('• ${p.description}');
        if (p.evidence != null && p.evidence!.isNotEmpty) text.writeln('  Evidence: "${p.evidence}"');
      }
      text.writeln();
    }
    if (_proposal!.solutions.isNotEmpty) {
      text.writeln('Recommended Solutions:');
      for (final s in _proposal!.solutions) {
        text.writeln('• ${s.service}: ${s.description} (${s.monthlyCost}/mo, saves ${s.timeSaved})');
      }
      text.writeln();
    }
    if (_proposal!.scopeDeliverables.isNotEmpty) {
      text.writeln('Scope of Work:');
      for (int i = 0; i < _proposal!.scopeDeliverables.length; i++) {
        text.writeln('${i + 1}. ${_proposal!.scopeDeliverables[i]}');
      }
      text.writeln();
    }
    if (_proposal!.scopeExcluded.isNotEmpty) {
      text.writeln('Not Included:');
      for (final e in _proposal!.scopeExcluded) { text.writeln('• $e'); }
      text.writeln();
    }
    text.writeln('Time Saved: ${_proposal!.totalTimeSaved}');
    text.writeln('Monthly Cost: ${_proposal!.estimatedMonthlyCost}');
    text.writeln('ROI: ${_proposal!.roiPercentage}');
    if (_proposal!.nextSteps.isNotEmpty) {
      text.writeln();
      text.writeln('Next Steps:');
      for (final ns in _proposal!.nextSteps) { text.writeln('• $ns'); }
    }
    if (_proposal!.closingLine != null) {
      text.writeln();
      text.writeln(_proposal!.closingLine);
    }

    Clipboard.setData(ClipboardData(text: text.toString()));
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Proposal copied to clipboard!'),
      backgroundColor: Color(0xFF00D2D3), duration: Duration(seconds: 2)));
  }
}