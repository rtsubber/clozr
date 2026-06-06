import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../models/meeting.dart';
import '../services/meeting_storage.dart';
import '../main.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  List<Meeting> _recentMeetings = [];
  bool _isCheckingAuth = true;

  @override
  void initState() {
    super.initState();
    _checkAuth();
  }

  Future<void> _checkAuth() async {
    final auth = ref.read(authProvider);
    await auth.loadFromStorage();
    if (!mounted) return;
    
    // Just update auth state, don't redirect - show inline login if needed
    setState(() => _isCheckingAuth = false);
    
    if (auth.isAuthenticated) {
      _loadMeetings();
    }
  }

  Future<void> _loadMeetings() async {
    final auth = ref.read(authProvider);
    final meetings = await MeetingStorage.loadAll(auth);
    if (mounted) {
      setState(() => _recentMeetings = meetings);
    }
  }

  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoggingIn = false;
  String? _loginError;

  Widget _buildLoginScreen(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D12),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Logo
                Container(
                  width: 64, height: 64,
                  decoration: BoxDecoration(
                    color: const Color(0xFF6C5CE7).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(Icons.mic_rounded, color: Color(0xFF6C5CE7), size: 32),
                ),
                const SizedBox(height: 24),
                const Text('The Clozr', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: Color(0xFFE8E8F0))),
                const SizedBox(height: 8),
                const Text('AI Meeting Assistant', style: TextStyle(fontSize: 14, color: Color(0xFF8B8BA0))),
                const SizedBox(height: 32),
                
                // Email field
                TextField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  style: const TextStyle(color: Color(0xFFE8E8F0)),
                  decoration: InputDecoration(
                    hintText: 'Email',
                    hintStyle: const TextStyle(color: Color(0xFF8B8BA0)),
                    filled: true,
                    fillColor: const Color(0xFF16161D),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF2A2A3A))),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF2A2A3A))),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF6C5CE7))),
                  ),
                ),
                const SizedBox(height: 12),
                
                // Password field
                TextField(
                  controller: _passwordController,
                  obscureText: true,
                  style: const TextStyle(color: Color(0xFFE8E8F0)),
                  decoration: InputDecoration(
                    hintText: 'Password',
                    hintStyle: const TextStyle(color: Color(0xFF8B8BA0)),
                    filled: true,
                    fillColor: const Color(0xFF16161D),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF2A2A3A))),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF2A2A3A))),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF6C5CE7))),
                  ),
                ),
                const SizedBox(height: 8),
                
                // Error message
                if (_loginError != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(_loginError!, style: const TextStyle(color: Color(0xFFFF6B6B), fontSize: 13)),
                  ),
                
                // Login button
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _isLoggingIn ? null : _handleLogin,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF6C5CE7),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: _isLoggingIn
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Text('Log In', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  ),
                ),
                const SizedBox(height: 12),
                
                // Register link
                TextButton(
                  onPressed: () => context.go('/login'),
                  child: const Text('Create Account', style: TextStyle(color: Color(0xFF8B8BA0))),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _handleLogin() async {
    setState(() {
      _isLoggingIn = true;
      _loginError = null;
    });
    try {
      final auth = ref.read(authProvider);
      final success = await auth.login(email: _emailController.text.trim(), password: _passwordController.text);
      if (success) {
        setState(() { _isLoggingIn = false; });
        _loadMeetings();
      } else {
        setState(() {
          _isLoggingIn = false;
          _loginError = 'Invalid email or password';
        });
      }
    } catch (e) {
      setState(() {
        _isLoggingIn = false;
        _loginError = 'Connection error. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Show loading while checking auth
    if (_isCheckingAuth) {
      return const Scaffold(
        backgroundColor: Color(0xFF0D0D12),
        body: Center(
          child: CircularProgressIndicator(color: Color(0xFF6C5CE7)),
        ),
      );
    }
    
    // Show inline login form if not authenticated
    final auth = ref.watch(authProvider);
    if (!auth.isAuthenticated) {
      return _buildLoginScreen(context);
    }
    
    // Refresh meetings list when returning from meeting
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadMeetings());
    
    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            // ── Header ──
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Good ${_greeting()}',
                                style: const TextStyle(
                                    color: Color(0xFF8B8BA0), fontSize: 15)),
                            const SizedBox(height: 2),
                            const Text('The Clozr',
                                style: TextStyle(
                                    fontSize: 32, fontWeight: FontWeight.w800,
                                    color: Color(0xFFE8E8F0))),
                          ],
                        ),
                        Container(
                          decoration: BoxDecoration(
                            color: const Color(0xFF16161D),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: const Color(0xFF2A2A3A)),
                          ),
                          child: IconButton(
                            icon: const Icon(Icons.settings_outlined, size: 22),
                            onPressed: () => context.push('/settings'),
                            color: const Color(0xFF8B8BA0),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          decoration: BoxDecoration(
                            color: const Color(0xFF6C5CE7).withOpacity(0.15),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: const Color(0xFF6C5CE7)),
                          ),
                          child: IconButton(
                            icon: const Icon(Icons.workspace_premium_outlined, size: 22),
                            onPressed: () => context.push('/pricing'),
                            color: const Color(0xFF6C5CE7),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 32),

                    // ── Hero: Start Meeting ──
                    GestureDetector(
                      onTap: () => context.push('/meeting'),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(28),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [Color(0xFF6C5CE7), Color(0xFF4834D4)],
                          ),
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF6C5CE7).withValues(alpha: 0.3),
                              blurRadius: 24,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: Column(
                          children: [
                            Container(
                              width: 64, height: 64,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: const Icon(Icons.mic_rounded, size: 32, color: Colors.white),
                            ),
                            const SizedBox(height: 16),
                            const Text('Start Meeting',
                                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: Colors.white)),
                            const SizedBox(height: 6),
                            Text('Tap to listen, transcribe & close',
                                style: TextStyle(fontSize: 14, color: Colors.white.withValues(alpha: 0.7))),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),

                    // ── Wake word hint (Coming Soon) ──
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF16161D),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFF2A2A3A)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 36, height: 36,
                            decoration: BoxDecoration(
                              color: const Color(0xFF00D2D3).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.hearing, size: 18, color: Color(0xFF00D2D3)),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text('Voice Activation',
                                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF6C5CE7),
                                        borderRadius: const BorderRadius.all(Radius.circular(4)),
                                      ),
                                      child: const Text('Coming Soon',
                                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.white)),
                                    ),
                                  ],
                                ),
                                SizedBox(height: 2),
                                Text('Say "Hey Clozr" to start hands-free',
                                    style: TextStyle(fontSize: 12, color: Color(0xFF8B8BA0))),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),

                    // ── Catalog shortcut ──
                    GestureDetector(
                      onTap: () => context.push('/catalog'),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF16161D),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0xFF2A2A3A)),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 36, height: 36,
                              decoration: BoxDecoration(
                                color: const Color(0xFF6C5CE7).withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(Icons.auto_awesome, size: 18, color: Color(0xFF6C5CE7)),
                            ),
                            const SizedBox(width: 12),
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Service Catalog',
                                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                                  SizedBox(height: 2),
                                  Text('Customize services Clozr detects & proposes',
                                      style: TextStyle(fontSize: 12, color: Color(0xFF8B8BA0))),
                                ],
                              ),
                            ),
                            Transform.rotate(
                              angle: 3.14159 / 2,
                              child: const Icon(Icons.chevron_right, color: Color(0xFF8B8BA0), size: 20),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),

            // ── Stats Row ──
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Row(
                  children: [
                    _statChip(context, Icons.record_voice_over_outlined, '${_recentMeetings.length}', 'Meetings'),
                    const SizedBox(width: 10),
                    _statChip(context, Icons.auto_awesome_outlined, '${_recentMeetings.fold<int>(0, (sum, m) => sum + m.workflowCount)}', 'Workflows'),
                    const SizedBox(width: 10),
                    _statChip(context, Icons.description_outlined, '${_recentMeetings.where((m) => m.summary != null).length}', 'Summarized'),
                  ],
                ),
              ),
            ),

            // ── Recent Meetings ──
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(24, 24, 24, 8),
                child: Text('Recent Meetings',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              ),
            ),

            _recentMeetings.isEmpty
                ? SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 64),
                      child: Column(
                        children: [
                          Container(
                            width: 72, height: 72,
                            decoration: BoxDecoration(
                              color: const Color(0xFF16161D),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: const Color(0xFF2A2A3A)),
                            ),
                            child: const Icon(Icons.mic_off_rounded, size: 32, color: Color(0xFF8B8BA0)),
                          ),
                          const SizedBox(height: 16),
                          const Text('No meetings yet',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 6),
                          const Text('Start your first meeting to see it here',
                              style: TextStyle(fontSize: 13, color: Color(0xFF8B8BA0))),
                        ],
                      ),
                    ),
                  )
                : SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) => _meetingCard(context, _recentMeetings[index]),
                        childCount: _recentMeetings.length,
                      ),
                    ),
                  ),

            const SliverToBoxAdapter(child: SizedBox(height: 100)),
          ],
        ),
      ),
    );
  }

  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'morning';
    if (hour < 17) return 'afternoon';
    return 'evening';
  }

  Widget _statChip(BuildContext context, IconData icon, String value, String label) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF16161D),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFF2A2A3A)),
        ),
        child: Column(
          children: [
            Icon(icon, color: const Color(0xFF6C5CE7), size: 20),
            const SizedBox(height: 6),
            Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 2),
            Text(label, style: const TextStyle(fontSize: 11, color: Color(0xFF8B8BA0))),
          ],
        ),
      ),
    );
  }

  Widget _meetingCard(BuildContext context, Meeting meeting) {
    return Dismissible(
      key: ValueKey(meeting.id),
      direction: DismissDirection.endToStart,
      confirmDismiss: (direction) async {
        return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: const Color(0xFF16161D),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: Color(0xFF2A2A3A))),
            title: const Text('Delete Meeting?', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
            content: Text('This will permanently delete "${meeting.title ?? 'Untitled Meeting'}".', style: const TextStyle(color: Color(0xFF8B8BA0))),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Cancel', style: TextStyle(color: Color(0xFF8B8BA0))),
              ),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Delete', style: TextStyle(color: Color(0xFFFF6B6B), fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ) ?? false;
      },
      onDismissed: (direction) async {
        final auth = ref.read(authProvider);
        if (auth.isAuthenticated) {
          try {
            await http.delete(
              Uri.parse('${auth.apiUrl}/api/meetings/${meeting.id}'),
              headers: auth.authHeaders,
            );
          } catch (_) {}
        }
        // Remove from local state
        setState(() {
          _recentMeetings.removeWhere((m) => m.id == meeting.id);
        });
      },
      background: Container(
        margin: const EdgeInsets.only(bottom: 10),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: const Color(0xFFFF6B6B).withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Icon(Icons.delete_outline, color: Color(0xFFFF6B6B), size: 28),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF16161D),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFF2A2A3A)),
        ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => context.push('/meeting/${meeting.id}'),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 44, height: 44,
                  decoration: BoxDecoration(
                    color: const Color(0xFF6C5CE7).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.description_outlined, color: Color(0xFF6C5CE7), size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(meeting.title ?? 'Untitled Meeting',
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                      const SizedBox(height: 3),
                      Text('${meeting.dateFormatted} · ${meeting.workflowCount} workflows',
                          style: const TextStyle(fontSize: 12, color: Color(0xFF8B8BA0))),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: meeting.workflowCount > 0
                        ? const Color(0xFF00D2D3).withValues(alpha: 0.15)
                        : const Color(0xFF2A2A3A),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    meeting.workflowCount > 0 ? '${meeting.workflowCount} found' : 'New',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: meeting.workflowCount > 0
                          ? const Color(0xFF00D2D3)
                          : const Color(0xFF8B8BA0),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      ),
    );
  }
}