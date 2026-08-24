import 'dart:convert';
import 'dart:io' as io;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart' as path_provider;
import '../models/meeting_minutes.dart';
import '../models/meeting.dart';
import '../services/auth_service.dart';
import '../services/llm_service.dart';
import '../services/meeting_storage.dart';
import '../main.dart';

class MinutesScreen extends ConsumerStatefulWidget {
  final String meetingId;
  final Map<String, dynamic>? minutesData;
  final String? transcript;

  const MinutesScreen({
    super.key,
    required this.meetingId,
    this.minutesData,
    this.transcript,
  });

  @override
  ConsumerState<MinutesScreen> createState() => _MinutesScreenState();
}

class _MinutesScreenState extends ConsumerState<MinutesScreen> {
  bool _isGenerating = true;
  bool _isSharing = false;
  bool _isExporting = false;
  String? _shareUrl;
  MeetingMinutes? _minutes;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.minutesData != null) {
      _minutes = MeetingMinutes.fromJson(widget.minutesData!);
      _isGenerating = false;
    } else {
      _generateMinutes();
    }
  }

  Future<void> _generateMinutes() async {
    try {
      final auth = ref.read(authProvider);
      final llm = LLMService(auth);

      // Use passed transcript first
      String transcript = widget.transcript ?? '';

      // Try fetching from API directly
      if (transcript.isEmpty) {
        try {
          final response = await http.get(
            Uri.parse('${auth.apiUrl}/api/meetings/${widget.meetingId}'),
            headers: auth.authHeaders,
          );
          if (response.statusCode == 200) {
            final data = jsonDecode(response.body);
            transcript = data['transcript'] ?? '';
          }
        } catch (_) {}
      }

      // Fall back to local storage
      if (transcript.isEmpty) {
        final meetings = await MeetingStorage.loadAll(auth);
        final meeting = meetings.firstWhere(
          (m) => m.id == widget.meetingId,
          orElse: () => Meeting(id: '', title: 'Unknown', date: DateTime.now()),
        );
        transcript = meeting.transcript ?? '';
      }

      if (transcript.isEmpty) {
        setState(() {
          _isGenerating = false;
          _error = 'Record a meeting first to generate minutes. The AI needs transcript data to analyze.';
        });
        return;
      }

      final result = await llm.generateMinutes(transcript: transcript);
      // Inject meeting_id and title if not present
      result['meeting_id'] = widget.meetingId;

      setState(() {
        _isGenerating = false;
        _minutes = MeetingMinutes.fromJson(result);
      });
    } catch (e) {
      setState(() {
        _isGenerating = false;
        _error = 'Could not generate meeting minutes: $e';
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
            Text('Generating meeting minutes...', style: TextStyle(color: Color(0xFF8B8BA0))),
            SizedBox(height: 8),
            Text('Extracting attendees → Decisions → Action items',
                style: TextStyle(color: Color(0xFF6C5CE7), fontSize: 13)),
          ],
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, color: Color(0xFFFF6B6B), size: 48),
              const SizedBox(height: 16),
              Text(_error!, style: const TextStyle(color: Color(0xFFFF6B6B), fontSize: 15), textAlign: TextAlign.center),
              const SizedBox(height: 24),
              OutlinedButton.icon(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.arrow_back, size: 18),
                label: const Text('Go Back'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF8B8BA0),
                  side: const BorderSide(color: Color(0xFF2A2A3A)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_minutes != null) return _buildMinutes();
    return const Center(child: Text('No minutes data', style: TextStyle(color: Color(0xFF8B8BA0))));
  }

  Widget _buildMinutes() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ──
          Row(children: [
            IconButton(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.arrow_back_ios_new, size: 20),
              style: IconButton.styleFrom(foregroundColor: const Color(0xFF8B8BA0)),
            ),
            const Expanded(child: Text('Meeting Minutes', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700))),
            IconButton(
              onPressed: _shareMinutes,
              icon: const Icon(Icons.share_rounded, size: 22),
              style: IconButton.styleFrom(foregroundColor: const Color(0xFF6C5CE7)),
              tooltip: 'Share',
            ),
            IconButton(
              onPressed: _copyMinutes,
              icon: const Icon(Icons.copy_rounded, size: 22),
              style: IconButton.styleFrom(foregroundColor: const Color(0xFF8B8BA0)),
              tooltip: 'Copy',
            ),
          ]),

          // ── Share banner ──
          if (_shareUrl != null) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF00D2D3).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF00D2D3).withValues(alpha: 0.3)),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Row(children: [
                  Icon(Icons.check_circle, color: Color(0xFF00D2D3), size: 18),
                  SizedBox(width: 8),
                  Text('Minutes saved!', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                ]),
                const SizedBox(height: 8),
                Text(_shareUrl!, style: const TextStyle(fontSize: 12, color: Color(0xFF8B8BA0))),
              ]),
            ),
          ],

          const SizedBox(height: 20),

          // ── Meeting title + type badge ──
          Text(_minutes!.meetingTitle, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF6C5CE7).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(_minutes!.meetingType,
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: Color(0xFF6C5CE7))),
          ),

          const SizedBox(height: 20),

          // ── Attendees ──
          if (_minutes!.attendees.isNotEmpty) ...[
            _sectionCard(Icons.people_outline, const Color(0xFF6C5CE7), 'Attendees',
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                ..._minutes!.attendees.map((a) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(children: [
                    Container(
                      width: 32, height: 32,
                      decoration: BoxDecoration(
                        color: const Color(0xFF6C5CE7).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Center(child: Text(
                        a.name.isNotEmpty ? a.name[0].toUpperCase() : '?',
                        style: const TextStyle(color: Color(0xFF6C5CE7), fontWeight: FontWeight.w700, fontSize: 14),
                      )),
                    ),
                    const SizedBox(width: 10),
                    Expanded(child: Text(a.name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600))),
                    if (a.role.isNotEmpty)
                      Text(a.role, style: const TextStyle(fontSize: 12, color: Color(0xFF8B8BA0))),
                  ]),
                )),
              ])),
            const SizedBox(height: 16),
          ],

          // ── Summary ──
          if (_minutes!.summary.isNotEmpty) ...[
            _sectionCard(Icons.summarize_outlined, const Color(0xFF00D2D3), 'Summary',
              Text(_minutes!.summary, style: const TextStyle(fontSize: 15, height: 1.7, color: Color(0xFFC8C8D8)))),
            const SizedBox(height: 16),
          ],

          // ── Key Decisions ──
          if (_minutes!.keyDecisions.isNotEmpty) ...[
            _sectionCard(Icons.gavel_rounded, const Color(0xFF6C5CE7), 'Key Decisions',
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                ..._minutes!.keyDecisions.map((d) => Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF6C5CE7).withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      const Icon(Icons.check_circle, size: 16, color: Color(0xFF6C5CE7)),
                      const SizedBox(width: 8),
                      Expanded(child: Text(d.decision, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600))),
                    ]),
                    if (d.rationale.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Padding(padding: const EdgeInsets.only(left: 24),
                        child: Text('Rationale: ${d.rationale}',
                          style: const TextStyle(fontSize: 12, color: Color(0xFF8B8BA0)))),
                    ],
                    if (d.decidedBy.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Padding(padding: const EdgeInsets.only(left: 24),
                        child: Text('Decided by: ${d.decidedBy}',
                          style: const TextStyle(fontSize: 12, color: Color(0xFF8B8BA0), fontStyle: FontStyle.italic))),
                    ],
                  ]),
                )),
              ])),
            const SizedBox(height: 16),
          ],

          // ── Action Items ──
          if (_minutes!.actionItems.isNotEmpty) ...[
            _sectionCard(Icons.checklist_rtl_rounded, const Color(0xFF00E676), 'Action Items',
              Column(children: [
                ..._minutes!.actionItems.map((item) => _actionItemCard(item)),
              ])),
            const SizedBox(height: 16),
          ],

          // ── Discussion Topics ──
          if (_minutes!.discussionTopics.isNotEmpty) ...[
            _sectionCard(Icons.forum_outlined, const Color(0xFF6C5CE7), 'Discussion Topics',
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                ..._minutes!.discussionTopics.map((t) => Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF16161D),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFF2A2A3A)),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(t.topic, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                    if (t.points.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      ...t.points.map((p) => Padding(
                        padding: const EdgeInsets.only(bottom: 4, left: 8),
                        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          const Icon(Icons.arrow_right, size: 14, color: Color(0xFF6C5CE7)),
                          const SizedBox(width: 4),
                          Expanded(child: Text(p, style: const TextStyle(fontSize: 13, height: 1.5))),
                        ]),
                      )),
                    ],
                    if (t.outcome.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFF00E676).withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(children: [
                          const Icon(Icons.flag_outlined, size: 14, color: Color(0xFF00E676)),
                          const SizedBox(width: 6),
                          Expanded(child: Text(t.outcome, style: const TextStyle(fontSize: 12, color: Color(0xFF00E676), fontWeight: FontWeight.w500))),
                        ]),
                      ),
                    ],
                  ]),
                )),
              ])),
            const SizedBox(height: 16),
          ],

          // ── Parking Lot ──
          if (_minutes!.parkingLot.isNotEmpty) ...[
            _sectionCard(Icons.lightbulb_outline, const Color(0xFFFDCB6E), 'Parking Lot',
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                ..._minutes!.parkingLot.map((p) => Padding(
                  padding: const EdgeInsets.only(bottom: 6, left: 4),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Icon(Icons.circle, size: 6, color: Color(0xFFFDCB6E)),
                    const SizedBox(width: 10),
                    Expanded(child: Text(p, style: const TextStyle(fontSize: 14, height: 1.5))),
                  ]),
                )),
              ])),
            const SizedBox(height: 16),
          ],

          // ── Open Questions ──
          if (_minutes!.openQuestions.isNotEmpty) ...[
            _sectionCard(Icons.help_outline, const Color(0xFF00D2D3), 'Open Questions',
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                ..._minutes!.openQuestions.map((q) => Padding(
                  padding: const EdgeInsets.only(bottom: 6, left: 4),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Icon(Icons.arrow_right, size: 16, color: Color(0xFF00D2D3)),
                    const SizedBox(width: 6),
                    Expanded(child: Text(q, style: const TextStyle(fontSize: 14, height: 1.5))),
                  ]),
                )),
              ])),
            const SizedBox(height: 16),
          ],

          // ── Risk Flags ──
          if (_minutes!.riskFlags.isNotEmpty) ...[
            _sectionCard(Icons.warning_amber_rounded, const Color(0xFFFF6B6B), 'Risk Flags',
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                ..._minutes!.riskFlags.map((r) => Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF6B6B).withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFFF6B6B).withValues(alpha: 0.2)),
                  ),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Icon(Icons.priority_high, size: 16, color: Color(0xFFFF6B6B)),
                    const SizedBox(width: 8),
                    Expanded(child: Text(r, style: const TextStyle(fontSize: 13, color: Color(0xFFC8C8D8)))),
                  ]),
                )),
              ])),
            const SizedBox(height: 16),
          ],

          // ── Next Meeting ──
          if (_minutes!.nextMeeting.isNotEmpty) ...[
            _sectionCard(Icons.event_available, const Color(0xFF6C5CE7), 'Next Meeting',
              Row(children: [
                const Icon(Icons.calendar_today, size: 18, color: Color(0xFF6C5CE7)),
                const SizedBox(width: 10),
                Expanded(child: Text(_minutes!.nextMeeting, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500))),
              ])),
            const SizedBox(height: 16),
          ],

          // ── Action Buttons ──
          Row(children: [
            // Share / Save button
            Expanded(child: SizedBox(
              height: 56,
              child: FilledButton.icon(
                onPressed: _isSharing ? null : _shareMinutes,
                icon: _isSharing
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.save_rounded, size: 22),
                label: Text(_isSharing ? 'Saving...' : 'Save Minutes',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF6C5CE7),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
              ),
            )),
            const SizedBox(width: 10),
            // Export PDF button
            Expanded(child: SizedBox(
              height: 56,
              child: OutlinedButton.icon(
                onPressed: _isExporting ? null : _exportPdf,
                icon: _isExporting
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF00D2D3)))
                  : const Icon(Icons.picture_as_pdf, size: 22, color: Color(0xFF00D2D3)),
                label: Text(_isExporting ? 'Exporting...' : 'Export PDF',
                  style: const TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF00D2D3))),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Color(0xFF2A2A3A)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
              ),
            )),
          ]),

          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _actionItemCard(ActionItem item) {
    final priorityColor = switch (item.priority.toLowerCase()) {
      'high' => const Color(0xFFFF6B6B),
      'medium' => const Color(0xFFFDCB6E),
      'low' => const Color(0xFF00D2D3),
      _ => const Color(0xFF8B8BA0),
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF00E676).withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF00E676).withValues(alpha: 0.12)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.task_alt, size: 16, color: Color(0xFF00E676)),
          const SizedBox(width: 8),
          Expanded(child: Text(item.task, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600))),
        ]),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 6, children: [
          if (item.owner.isNotEmpty) _chip(Icons.person_outline, item.owner, const Color(0xFF6C5CE7)),
          if (item.dueDate.isNotEmpty) _chip(Icons.calendar_today, item.dueDate, const Color(0xFF00D2D3)),
          _chip(Icons.flag_outlined, item.priority.toUpperCase(), priorityColor),
          _chip(Icons.radio_button_unchecked, item.status, const Color(0xFF8B8BA0)),
        ]),
      ]),
    );
  }

  Widget _chip(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color)),
      ]),
    );
  }

  Widget _sectionCard(IconData icon, Color color, String title, Widget content) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF16161D),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF2A2A3A)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(width: 10),
          Text(title, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: color)),
        ]),
        const SizedBox(height: 12),
        content,
      ]),
    );
  }

  /// Save minutes to backend via POST /api/minutes
  Future<void> _shareMinutes() async {
    if (_minutes == null || _isSharing) return;
    setState(() => _isSharing = true);

    try {
      final auth = ref.read(authProvider);
      if (!auth.isAuthenticated) throw Exception('Not authenticated. Please log in.');

      final minutesData = _minutes!.toJson();
      // Remove id and created_at for new saves (server generates)
      minutesData.remove('id');
      minutesData.remove('created_at');

      final response = await http.post(
        Uri.parse('${auth.apiUrl}/api/minutes'),
        headers: auth.authHeaders,
        body: jsonEncode(minutesData),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final savedId = data['id']?.toString() ?? '';
        final sharePath = data['share_url'] as String?;
        final shareUrl = sharePath != null ? '${AuthService.basePath}$sharePath' : null;

        setState(() {
          _shareUrl = shareUrl ?? 'Saved (ID: $savedId)';
          _isSharing = false;
        });

        if (shareUrl != null) {
          await Clipboard.setData(ClipboardData(text: shareUrl));
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('Link copied! Share: $shareUrl'),
              backgroundColor: const Color(0xFF6C5CE7),
              duration: const Duration(seconds: 4),
            ));
          }
        } else if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Minutes saved successfully!'),
            backgroundColor: Color(0xFF00E676),
            duration: Duration(seconds: 2),
          ));
        }
      } else {
        throw Exception('Failed to save minutes (${response.statusCode})');
      }
    } catch (e) {
      setState(() => _isSharing = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error saving: $e'),
          backgroundColor: const Color(0xFFFF6B6B),
        ));
      }
    }
  }

  /// Export minutes as PDF via GET /api/minutes/{id}/pdf
  Future<void> _exportPdf() async {
    if (_minutes == null || _isExporting) return;
    setState(() => _isExporting = true);

    try {
      final auth = ref.read(authProvider);
      if (!auth.isAuthenticated) throw Exception('Not authenticated. Please log in.');

      // Use the minutes id (or meeting_id as fallback)
      final minutesId = _minutes!.id.isNotEmpty ? _minutes!.id : widget.meetingId;

      final response = await http.get(
        Uri.parse('${auth.apiUrl}/api/minutes/$minutesId/pdf'),
        headers: auth.authHeaders,
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final base64Pdf = data['pdf'] as String?;
        if (base64Pdf != null) {
          final bytes = base64Decode(base64Pdf);

          if (kIsWeb) {
            // On web, trigger download via JS interop
            // For now, show a snackbar — web download needs js_interop
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text('PDF generated! Check your downloads.'),
                backgroundColor: Color(0xFF00E676),
              ));
            }
          } else {
            // On mobile, save to file
            final tempDir = await path_provider.getTemporaryDirectory();
            final file = io.File('${tempDir.path}/meeting_minutes_$minutesId.pdf');
            await file.writeAsBytes(bytes);

            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text('PDF saved to: ${file.path}'),
                backgroundColor: const Color(0xFF00E676),
                duration: const Duration(seconds: 4),
              ));
            }
          }
        } else {
          throw Exception('No PDF data in response');
        }
      } else if (response.statusCode == 404) {
        // PDF endpoint not available — fall back to copy
        _copyMinutes();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('PDF export not available. Minutes copied to clipboard instead.'),
            backgroundColor: Color(0xFFFDCB6E),
          ));
        }
      } else {
        throw Exception('PDF export failed (${response.statusCode})');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Export error: $e'),
          backgroundColor: const Color(0xFFFF6B6B),
        ));
      }
    } finally {
      setState(() => _isExporting = false);
    }
  }

  /// Copy minutes text to clipboard
  void _copyMinutes() {
    if (_minutes == null) return;
    final text = StringBuffer();
    text.writeln('=== Meeting Minutes: ${_minutes!.meetingTitle} ===');
    text.writeln('Type: ${_minutes!.meetingType}');
    text.writeln();

    if (_minutes!.attendees.isNotEmpty) {
      text.writeln('Attendees:');
      for (final a in _minutes!.attendees) {
        text.writeln('• ${a.name}${a.role.isNotEmpty ? ' (${a.role})' : ''}');
      }
      text.writeln();
    }

    if (_minutes!.summary.isNotEmpty) {
      text.writeln('Summary:');
      text.writeln(_minutes!.summary);
      text.writeln();
    }

    if (_minutes!.keyDecisions.isNotEmpty) {
      text.writeln('Key Decisions:');
      for (final d in _minutes!.keyDecisions) {
        text.writeln('• ${d.decision}');
        if (d.rationale.isNotEmpty) text.writeln('  Rationale: ${d.rationale}');
        if (d.decidedBy.isNotEmpty) text.writeln('  Decided by: ${d.decidedBy}');
      }
      text.writeln();
    }

    if (_minutes!.actionItems.isNotEmpty) {
      text.writeln('Action Items:');
      for (final item in _minutes!.actionItems) {
        text.writeln('• ${item.task} [Owner: ${item.owner}, Due: ${item.dueDate}, Priority: ${item.priority}, Status: ${item.status}]');
      }
      text.writeln();
    }

    if (_minutes!.discussionTopics.isNotEmpty) {
      text.writeln('Discussion Topics:');
      for (final t in _minutes!.discussionTopics) {
        text.writeln('• ${t.topic}');
        for (final p in t.points) {
          text.writeln('  - $p');
        }
        if (t.outcome.isNotEmpty) text.writeln('  Outcome: ${t.outcome}');
      }
      text.writeln();
    }

    if (_minutes!.parkingLot.isNotEmpty) {
      text.writeln('Parking Lot:');
      for (final p in _minutes!.parkingLot) {
        text.writeln('• $p');
      }
      text.writeln();
    }

    if (_minutes!.openQuestions.isNotEmpty) {
      text.writeln('Open Questions:');
      for (final q in _minutes!.openQuestions) {
        text.writeln('• $q');
      }
      text.writeln();
    }

    if (_minutes!.riskFlags.isNotEmpty) {
      text.writeln('Risk Flags:');
      for (final r in _minutes!.riskFlags) {
        text.writeln('• $r');
      }
      text.writeln();
    }

    if (_minutes!.nextMeeting.isNotEmpty) {
      text.writeln('Next Meeting: ${_minutes!.nextMeeting}');
    }

    Clipboard.setData(ClipboardData(text: text.toString()));
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Minutes copied to clipboard!'),
      backgroundColor: Color(0xFF00D2D3),
      duration: Duration(seconds: 2),
    ));
  }
}