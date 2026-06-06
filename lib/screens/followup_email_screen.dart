import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import '../models/meeting.dart';
import '../services/auth_service.dart';
import '../services/llm_service.dart';
import '../services/meeting_storage.dart';
import '../main.dart';

class FollowUpEmailScreen extends ConsumerStatefulWidget {
  final String meetingId;
  final Map<String, dynamic>? emailData;
  
  const FollowUpEmailScreen({super.key, required this.meetingId, this.emailData});

  @override
  ConsumerState<FollowUpEmailScreen> createState() => _FollowUpEmailScreenState();
}

class _FollowUpEmailScreenState extends ConsumerState<FollowUpEmailScreen> {
  bool _isGenerating = true;
  String? _error;
  String? _subject;
  String? _body;
  String? _psLine;
  String? _sendTiming;
  String? _confidenceLevel;
  String? _clientName;

  @override
  void initState() {
    super.initState();
    if (widget.emailData != null) {
      _parseEmailData(widget.emailData!);
      _isGenerating = false;
    } else {
      _generateEmail();
    }
  }

  void _parseEmailData(Map<String, dynamic> d) {
    final result = d['result'] as Map<String, dynamic>? ?? d;
    _subject = result['subject']?.toString();
    _body = result['body']?.toString();
    _psLine = result['ps_line']?.toString();
    _sendTiming = result['send_timing']?.toString();
    _confidenceLevel = result['confidence_level']?.toString();
    _clientName = result['client_name']?.toString() ?? d['meeting_data']?['client']?['name']?.toString();
  }

  Future<void> _generateEmail() async {
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
          _error = 'No transcript available. Record a meeting first.';
        });
        return;
      }
      
      final result = await llm.generateFollowUp(transcript: transcript);
      setState(() {
        _isGenerating = false;
        _parseEmailData(result);
      });
    } catch (e) {
      setState(() {
        _isGenerating = false;
        _error = 'Could not generate email: $e';
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
            Text('Drafting follow-up email...', style: TextStyle(color: Color(0xFF8B8BA0))),
            SizedBox(height: 8),
            Text('Analyzing meeting → Crafting personalized email', style: TextStyle(color: Color(0xFF6C5CE7), fontSize: 13)),
          ],
        ),
      );
    }
    if (_error != null) {
      return Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!, style: const TextStyle(color: Color(0xFFFF6B6B)))));
    }
    return _buildEmail();
  }

  Widget _buildEmail() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ──
          Row(children: [
            IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.arrow_back_ios_new, size: 20),
              style: IconButton.styleFrom(foregroundColor: const Color(0xFF8B8BA0))),
            const Expanded(child: Text('Follow-Up Email', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700))),
            IconButton(onPressed: _copyEmail, icon: const Icon(Icons.copy_rounded, size: 22),
              style: IconButton.styleFrom(foregroundColor: const Color(0xFF8B8BA0)), tooltip: 'Copy'),
          ]),

          const SizedBox(height: 20),

          // ── Confidence & Timing ──
          if (_confidenceLevel != null || _sendTiming != null) ...[
            Container(
              width: double.infinity, padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _confidenceLevel == 'warm' 
                  ? const Color(0xFF00E676).withValues(alpha: 0.08) 
                  : const Color(0xFF00D2D3).withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _confidenceLevel == 'warm'
                  ? const Color(0xFF00E676).withValues(alpha: 0.2)
                  : const Color(0xFF00D2D3).withValues(alpha: 0.2)),
              ),
              child: Row(children: [
                Icon(_confidenceLevel == 'warm' ? Icons.local_fire_department : Icons.schedule,
                  color: _confidenceLevel == 'warm' ? const Color(0xFF00E676) : const Color(0xFF00D2D3), size: 20),
                const SizedBox(width: 10),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  if (_confidenceLevel != null)
                    Text('Lead: ${_confidenceLevel!.substring(0, 1).toUpperCase()}${_confidenceLevel!.substring(1)}',
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14,
                        color: _confidenceLevel == 'warm' ? const Color(0xFF00E676) : const Color(0xFF00D2D3))),
                  if (_sendTiming != null)
                    Text('Send: ${_sendTiming!}', style: const TextStyle(fontSize: 12, color: Color(0xFF8B8BA0))),
                ])),
              ]),
            ),
            const SizedBox(height: 16),
          ],

          // ── Subject ──
          Container(
            width: double.infinity, padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: const Color(0xFF16161D), borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF2A2A3A))),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Subject', style: TextStyle(fontSize: 11, color: Color(0xFF8B8BA0), letterSpacing: 1)),
              const SizedBox(height: 6),
              Text(_subject ?? 'Follow-up', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            ]),
          ),
          const SizedBox(height: 16),

          // ── Email Body ──
          Container(
            width: double.infinity, padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(color: const Color(0xFF16161D), borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF2A2A3A))),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (_clientName != null && _clientName!.isNotEmpty) ...[
                Text('Hi ${_clientName!.split(' ').first},', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
                const SizedBox(height: 12),
              ],
              Text(_body ?? '', style: const TextStyle(fontSize: 15, height: 1.8, color: Color(0xFFC8C8D8))),
            ]),
          ),

          // ── P.S. Line ──
          if (_psLine != null && _psLine!.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity, padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: const Color(0xFF6C5CE7).withValues(alpha: 0.06), borderRadius: BorderRadius.circular(10)),
              child: Row(children: [
                const Icon(Icons.auto_awesome, size: 16, color: Color(0xFF6C5CE7)),
                const SizedBox(width: 8),
                Expanded(child: Text('P.S. ${_psLine!}', style: const TextStyle(fontSize: 13, fontStyle: FontStyle.italic, color: Color(0xFF8B8BA0)))),
              ]),
            ),
          ],

          const SizedBox(height: 24),

          // ── Copy button ──
          SizedBox(width: double.infinity, height: 56,
            child: FilledButton.icon(
              onPressed: _copyEmail,
              icon: const Icon(Icons.copy_rounded, size: 22),
              label: const Text('Copy Email to Clipboard', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFF6C5CE7),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
            )),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  void _copyEmail() {
    final text = StringBuffer();
    if (_subject != null) text.writeln('Subject: $_subject');
    text.writeln();
    if (_clientName != null && _clientName!.isNotEmpty) {
      text.writeln('Hi ${_clientName!.split(' ').first},');
      text.writeln();
    }
    text.writeln(_body ?? '');
    if (_psLine != null && _psLine!.isNotEmpty) {
      text.writeln();
      text.writeln('P.S. $_psLine');
    }

    Clipboard.setData(ClipboardData(text: text.toString()));
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Email copied to clipboard!'),
      backgroundColor: Color(0xFF00D2D3), duration: Duration(seconds: 2)));
  }
}