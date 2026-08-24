import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../main.dart';
import '../services/llm_service.dart';
import '../services/workflow_service.dart';

/// Screen for creating proposals from text input (paste or guided form).
/// Three modes: Paste, Tell me, Record (Record just navigates to MeetingScreen).
class TextInputScreen extends ConsumerStatefulWidget {
  final int initialTab;
  const TextInputScreen({super.key, this.initialTab = 0});

  @override
  ConsumerState<TextInputScreen> createState() => _TextInputScreenState();
}

class _TextInputScreenState extends ConsumerState<TextInputScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Paste tab state
  final _pasteController = TextEditingController();
  int _pasteCharCount = 0;
  static const int _maxChars = 50000;

  // Tell me tab state
  final _clientNameController = TextEditingController();
  final _needsController = TextEditingController();
  final _budgetController = TextEditingController();
  final _timelineController = TextEditingController();
  final _anythingElseController = TextEditingController();

  // Shared state
  bool _isLoading = false;
  bool _limitReached = false;
  int _meetingsRemaining = 5;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 3,
      vsync: this,
      initialIndex: widget.initialTab.clamp(0, 2),
    );
    _pasteController.addListener(_updatePasteCharCount);
    _checkFreeTierLimit();
  }

  void _updatePasteCharCount() {
    setState(() {
      _pasteCharCount = _pasteController.text.length;
    });
  }

  @override
  void dispose() {
    _pasteController.dispose();
    _clientNameController.dispose();
    _needsController.dispose();
    _budgetController.dispose();
    _timelineController.dispose();
    _anythingElseController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _checkFreeTierLimit() async {
    final auth = ref.read(authProvider);
    if (!auth.isAuthenticated) return;
    try {
      final response = await http.get(
        Uri.parse('${auth.apiUrl}/api/fingerprint/status'),
        headers: auth.authHeaders,
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _limitReached = data['limit_reached'] ?? false;
          _meetingsRemaining = data['remaining'] ?? 5;
        });
      }
    } catch (_) {}
  }

  void _showUpgradeModal() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF16161D),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFF2A2A3A)),
        ),
        title: const Row(
          children: [
            Icon(Icons.lock_outline, color: Color(0xFF6C5CE7)),
            SizedBox(width: 10),
            Text('Free Limit Reached', style: TextStyle(color: Colors.white)),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "You've used all 5 free meetings!",
              style: TextStyle(color: Colors.white, fontSize: 16),
            ),
            SizedBox(height: 12),
            Text(
              'Upgrade to Pro for:',
              style: TextStyle(color: Color(0xFF8B8BA0)),
            ),
            SizedBox(height: 8),
            _ProFeature('✔️  Unlimited meetings'),
            _ProFeature('✔️  AI proposals'),
            _ProFeature('✔️  Speaker diarization'),
            _ProFeature('✔️  Priority processing'),
            SizedBox(height: 8),
            Text(
              'Or delete old meetings to free up slots.',
              style: TextStyle(color: Color(0xFF8B8BA0), fontSize: 13),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Maybe Later', style: TextStyle(color: Color(0xFF8B8BA0))),
          ),
          Container(
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Color(0xFF6C5CE7), Color(0xFF00D2D3)]),
              borderRadius: BorderRadius.circular(8),
            ),
            child: TextButton(
              onPressed: () {
                Navigator.pop(context);
                context.push('/pricing');
              },
              child: const Text('Upgrade to Pro', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _generateProposalFromPaste() async {
    final text = _pasteController.text.trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please paste your meeting notes'), backgroundColor: Color(0xFFFF6B6B)),
      );
      return;
    }
    if (_limitReached) {
      _showUpgradeModal();
      return;
    }
    setState(() => _isLoading = true);

    try {
      final auth = ref.read(authProvider);
      // Generate title from first 50 chars
      final title = text.length > 50 ? '${text.substring(0, 50)}...' : text.replaceAll('\n', ' ');

      final response = await http.post(
        Uri.parse('${auth.apiUrl}/api/meetings'),
        headers: {...auth.authHeaders, 'Content-Type': 'application/json'},
        body: jsonEncode({
          'title': title,
          'transcript': text,
        }),
      );

      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final meetingId = data['id'] as String?;
        if (meetingId != null) {
          // Generate summary + detect workflows in parallel with proposal
          // (fire and forget — update meeting when results come back)
          try {
            final llm = LLMService(auth);
            final workflowService = WorkflowService(auth);

            llm.summarizeMeeting(text).then((summary) {
              http.patch(
                Uri.parse('${auth.apiUrl}/api/meetings/$meetingId'),
                headers: {...auth.authHeaders, 'Content-Type': 'application/json'},
                body: jsonEncode({'summary': summary}),
              ).catchError((_) {});
            }).catchError((_) {});

            workflowService.detectWorkflows(text).then((workflows) {
              http.patch(
                Uri.parse('${auth.apiUrl}/api/meetings/$meetingId'),
                headers: {...auth.authHeaders, 'Content-Type': 'application/json'},
                body: jsonEncode({'workflow_count': workflows.length}),
              ).catchError((_) {});
            }).catchError((_) {});
          } catch (_) {}

          // Generate proposal (blocking — user sees spinner)
          try {
            final llm = LLMService(auth);
            await llm.generateProposal(transcript: text);
          } catch (_) {}
          if (!mounted) return;
          context.go('/proposal/$meetingId');
        }
      } else if (response.statusCode == 403) {
        setState(() { _limitReached = true; });
        _showUpgradeModal();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${response.statusCode}'), backgroundColor: const Color(0xFFFF6B6B)),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Connection error: $e'), backgroundColor: const Color(0xFFFF6B6B)),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _generateProposalFromForm() async {
    final clientName = _clientNameController.text.trim();
    final needs = _needsController.text.trim();
    if (clientName.isEmpty || needs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Client name and needs are required'), backgroundColor: Color(0xFFFF6B6B)),
      );
      return;
    }
    if (_limitReached) {
      _showUpgradeModal();
      return;
    }
    setState(() => _isLoading = true);

    try {
      final auth = ref.read(authProvider);
      final budget = _budgetController.text.trim();
      final timeline = _timelineController.text.trim();
      final anythingElse = _anythingElseController.text.trim();

      // Construct structured transcript
      final transcript = StringBuffer();
      transcript.writeln('Client: $clientName');
      transcript.writeln('Needs: $needs');
      transcript.writeln('Budget: ${budget.isNotEmpty ? budget : "Not mentioned"}');
      transcript.writeln('Timeline: ${timeline.isNotEmpty ? timeline : "Not mentioned"}');
      if (anythingElse.isNotEmpty) {
        transcript.writeln('Additional context: $anythingElse');
      }

      final today = DateTime.now();
      final dateStr = '${today.month}/${today.day}/${today.year}';
      final title = 'Proposal for $clientName — $dateStr';

      final response = await http.post(
        Uri.parse('${auth.apiUrl}/api/meetings'),
        headers: {...auth.authHeaders, 'Content-Type': 'application/json'},
        body: jsonEncode({
          'title': title,
          'transcript': transcript.toString().trim(),
        }),
      );

      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final meetingId = data['id'] as String?;
        if (meetingId != null) {
          // Generate summary + detect workflows in parallel with proposal
          try {
            final llm = LLMService(auth);
            final workflowService = WorkflowService(auth);

            llm.summarizeMeeting(transcript.toString().trim()).then((summary) {
              http.patch(
                Uri.parse('${auth.apiUrl}/api/meetings/$meetingId'),
                headers: {...auth.authHeaders, 'Content-Type': 'application/json'},
                body: jsonEncode({'summary': summary}),
              ).catchError((_) {});
            }).catchError((_) {});

            workflowService.detectWorkflows(transcript.toString().trim()).then((workflows) {
              http.patch(
                Uri.parse('${auth.apiUrl}/api/meetings/$meetingId'),
                headers: {...auth.authHeaders, 'Content-Type': 'application/json'},
                body: jsonEncode({'workflow_count': workflows.length}),
              ).catchError((_) {});
            }).catchError((_) {});
          } catch (_) {}

          // Generate proposal (blocking — user sees spinner)
          try {
            final llm = LLMService(auth);
            await llm.generateProposal(transcript: transcript.toString().trim());
          } catch (_) {}
          if (!mounted) return;
          context.go('/proposal/$meetingId');
        }
      } else if (response.statusCode == 403) {
        setState(() { _limitReached = true; });
        _showUpgradeModal();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${response.statusCode}'), backgroundColor: const Color(0xFFFF6B6B)),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Connection error: $e'), backgroundColor: const Color(0xFFFF6B6B)),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);

    return Scaffold(
      backgroundColor: const Color(0xFF0D0D12),
      body: SafeArea(
        child: Column(
          children: [
            // ── Header with back button ──
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 16, 0),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new, color: Color(0xFFE8E8F0)),
                    onPressed: () => context.pop(),
                  ),
                  const Expanded(
                    child: Text('New Proposal',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Color(0xFFE8E8F0)),
                    ),
                  ),
                  // Remaining count badge
                  if (auth.isAuthenticated && !_limitReached)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: const Color(0xFF00D2D3).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: const Color(0xFF00D2D3).withValues(alpha: 0.3)),
                      ),
                      child: Text(
                        '$_meetingsRemaining free left',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF00D2D3)),
                      ),
                    ),
                ],
              ),
            ),

            // ── Tab Bar ──
            Container(
              margin: const EdgeInsets.fromLTRB(24, 8, 24, 0),
              decoration: BoxDecoration(
                color: const Color(0xFF16161D),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFF2A2A3A)),
              ),
              child: TabBar(
                controller: _tabController,
                indicatorSize: TabBarIndicatorSize.tab,
                indicator: BoxDecoration(
                  gradient: const LinearGradient(colors: [Color(0xFF6C5CE7), Color(0xFF4834D4)]),
                  borderRadius: BorderRadius.circular(12),
                ),
                dividerColor: Colors.transparent,
                labelColor: Colors.white,
                unselectedLabelColor: const Color(0xFF8B8BA0),
                labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                unselectedLabelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                padding: const EdgeInsets.all(4),
                tabs: const [
                  Tab(text: '📋  Paste'),
                  Tab(text: '💬  Tell me'),
                  Tab(text: '🎤  Record'),
                ],
              ),
            ),

            // ── Tab Content ──
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildPasteTab(),
                  _buildTellMeTab(),
                  _buildRecordTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── PASTE TAB ──
  Widget _buildPasteTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          const Text('Paste Meeting Notes',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Color(0xFFE8E8F0)),
          ),
          const SizedBox(height: 4),
          const Text('Paste your meeting transcript, notes, or a summary of what the client said.',
            style: TextStyle(fontSize: 13, color: Color(0xFF8B8BA0)),
          ),
          const SizedBox(height: 20),

          // Text area
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFF16161D),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFF2A2A3A)),
            ),
            child: TextField(
              controller: _pasteController,
              maxLines: 12,
              maxLength: _maxChars,
              style: const TextStyle(color: Color(0xFFE8E8F0), fontSize: 15, height: 1.5),
              decoration: InputDecoration(
                hintText: 'Paste your meeting notes, transcript, or client conversation summary...\n\nInclude what the client said about their needs, budget, timeline, and pain points.',
                hintStyle: const TextStyle(color: Color(0xFF8B8BA0), fontSize: 14, height: 1.5),
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
                contentPadding: const EdgeInsets.all(16),
                counterStyle: const TextStyle(color: Color(0xFF8B8BA0), fontSize: 12),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Tip
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF00D2D3).withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFF00D2D3).withValues(alpha: 0.2)),
            ),
            child: const Row(
              children: [
                Icon(Icons.lightbulb_outline, size: 18, color: Color(0xFF00D2D3)),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'The more detail you provide, the better your proposal will be.',
                    style: TextStyle(fontSize: 12, color: Color(0xFF00D2D3)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Generate button
          SizedBox(
            width: double.infinity,
            child: _buildGenerateButton(onPressed: _generateProposalFromPaste),
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  // ── TELL ME TAB ──
  Widget _buildTellMeTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          const Text('Tell me about the meeting',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Color(0xFFE8E8F0)),
          ),
          const SizedBox(height: 4),
          const Text('Answer a few questions and we\'ll build the proposal.',
            style: TextStyle(fontSize: 13, color: Color(0xFF8B8BA0)),
          ),
          const SizedBox(height: 24),

          // Client Name (required)
          _buildLabel('Client Name', required: true),
          const SizedBox(height: 6),
          _buildTextField(controller: _clientNameController, hint: 'e.g. Acme Corp, Springfield Dental'),
          const SizedBox(height: 18),

          // What they need (required)
          _buildLabel('What do they need?', required: true),
          const SizedBox(height: 6),
          _buildTextField(
            controller: _needsController,
            hint: 'Describe what the client is looking for...',
            maxLines: 4,
          ),
          const SizedBox(height: 18),

          // Budget (optional)
          _buildLabel('Budget mentioned'),
          const SizedBox(height: 6),
          _buildTextField(controller: _budgetController, hint: 'e.g. \$2,000-3,000/mo, \$10K total'),
          const SizedBox(height: 18),

          // Timeline (optional)
          _buildLabel('Timeline'),
          const SizedBox(height: 6),
          _buildTextField(controller: _timelineController, hint: 'e.g. ASAP, 2 weeks, end of Q3'),
          const SizedBox(height: 18),

          // Anything else (optional)
          _buildLabel('Anything else?'),
          const SizedBox(height: 6),
          _buildTextField(
            controller: _anythingElseController,
            hint: 'Pain points, competitors mentioned, decision maker info...',
            maxLines: 3,
          ),
          const SizedBox(height: 24),

          // Generate button
          SizedBox(
            width: double.infinity,
            child: _buildGenerateButton(onPressed: _generateProposalFromForm),
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  // ── RECORD TAB ──
  Widget _buildRecordTab() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 88, height: 88,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF6C5CE7), Color(0xFF4834D4)],
                ),
                borderRadius: BorderRadius.circular(28),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF6C5CE7).withValues(alpha: 0.3),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: const Icon(Icons.mic_rounded, size: 40, color: Colors.white),
            ),
            const SizedBox(height: 24),
            const Text('Record a Live Meeting',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: Color(0xFFE8E8F0)),
            ),
            const SizedBox(height: 8),
            const Text('Tap the button below to start recording your meeting.\nClozr will transcribe and generate a proposal automatically.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Color(0xFF8B8BA0), height: 1.5),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => context.push('/meeting'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF6C5CE7),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: const Text('Start Recording', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Shared UI Components ──

  Widget _buildGenerateButton({required VoidCallback onPressed}) {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF6C5CE7), Color(0xFF4834D4)],
        ),
        borderRadius: BorderRadius.circular(14),
        boxShadow: _isLoading ? [] : [
          BoxShadow(
            color: const Color(0xFF6C5CE7).withValues(alpha: 0.3),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: FilledButton(
        onPressed: _isLoading ? null : onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.white,
          disabledBackgroundColor: Colors.transparent,
          disabledForegroundColor: Colors.white54,
          padding: const EdgeInsets.symmetric(vertical: 18),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        child: _isLoading
          ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
          : Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.auto_awesome, size: 20),
                const SizedBox(width: 8),
                const Text('Generate Proposal', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              ],
            ),
      ),
    );
  }

  Widget _buildLabel(String text, {bool required = false}) {
    return RichText(
      text: TextSpan(
        children: [
          TextSpan(
            text: text,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFFE8E8F0)),
          ),
          if (required)
            const TextSpan(
              text: ' *',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF6C5CE7)),
            ),
        ],
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hint,
    int maxLines = 1,
  }) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      style: const TextStyle(color: Color(0xFFE8E8F0), fontSize: 15, height: 1.4),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Color(0xFF8B8BA0), fontSize: 14),
        filled: true,
        fillColor: const Color(0xFF16161D),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF2A2A3A)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF2A2A3A)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF6C5CE7)),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
    );
  }
}

class _ProFeature extends StatelessWidget {
  final String text;
  const _ProFeature(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 14)),
    );
  }
}