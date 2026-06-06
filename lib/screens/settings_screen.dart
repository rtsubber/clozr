import '../services/app_config.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../main.dart';


/// Settings screen — now shows account info instead of API keys (H1 fix)
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _wakeWordEnabled = false;
  Map<String, dynamic>? _accountInfo;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final auth = ref.read(authProvider);
    if (auth.isAuthenticated) {
      final info = await auth.getAccount();
      setState(() {
        _accountInfo = info;
        _isLoading = false;
      });
    } else {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _logout() async {
    final auth = ref.read(authProvider);
    await auth.logout();
    if (mounted) {
      context.go('/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D12),
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: const Color(0xFF0D0D12),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF6C5CE7)))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Account Section ──
                  _sectionHeader(context, 'Account', Icons.person_outline),
                  const SizedBox(height: 16),

                  Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF16161D),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFF2A2A3A)),
                    ),
                    child: Column(
                      children: [
                        if (_accountInfo != null) ...[
                          _infoRow(Icons.email_outlined, 'Email', _accountInfo!['email'] ?? 'Unknown'),
                          const Divider(color: Color(0xFF2A2A3A), height: 1),
                          _infoRow(Icons.business_outlined, 'Company', _accountInfo!['company'] ?? 'Not set'),
                          const Divider(color: Color(0xFF2A2A3A), height: 1),
                          _infoRow(Icons.palette_outlined, 'Brand', _accountInfo!['brand_name'] ?? 'The Clozr'),
                        ] else ...[
                          Padding(
                            padding: const EdgeInsets.all(20),
                            child: Text(
                              'Not signed in. Some features require an account.',
                              style: const TextStyle(color: Color(0xFF8B8BA0)),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),

                  // ── Connection Status ──
                  _sectionHeader(context, 'Connection', Icons.cloud_outlined),
                  const SizedBox(height: 4),
                  const Text('Server handles AI calls — no API keys needed.',
                      style: TextStyle(fontSize: 13, color: Color(0xFF8B8BA0))),
                  const SizedBox(height: 12),

                  Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF16161D),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFF2A2A3A)),
                    ),
                    child: Column(
                      children: [
                        _infoRow(Icons.dns_outlined, 'Backend', AppConfig.backendUrl),
                        const Divider(color: Color(0xFF2A2A3A), height: 1),
                        _infoRow(
                          Icons.security_outlined,
                          'Auth',
                          ref.read(authProvider).isAuthenticated ? 'Signed in' : 'Not signed in',
                        ),
                        const Divider(color: Color(0xFF2A2A3A), height: 1),
                        _infoRow(
                          Icons.psychology_outlined,
                          'LLM',
                          'Server proxy (Groq/OpenRouter)',
                        ),
                        const Divider(color: Color(0xFF2A2A3A), height: 1),
                        _infoRow(
                          Icons.visibility_outlined,
                          'Local-Eye',
                          'Server proxy',
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),

                  // ── Wake Word Section ──
                  _sectionHeader(context, 'Wake Word', Icons.hearing),
                  const SizedBox(height: 4),
                  const Text('Enable "Hey Jarvis" to start meetings hands-free.',
                      style: TextStyle(fontSize: 13, color: Color(0xFF8B8BA0))),
                  const SizedBox(height: 12),

                  Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF16161D),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFF2A2A3A)),
                    ),
                    child: SwitchListTile(
                      title: const Text('Enable Wake Word', style: TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: const Text('Coming soon — voice activation not yet available'),
                      value: false, // Disabled until Porcupine integration
                      onChanged: null, // Disabled
                      activeThumbColor: const Color(0xFF6C5CE7),
                    ),
                  ),
                  const SizedBox(height: 32),

                  // ── About Section ──
                  _sectionHeader(context, 'About', Icons.info_outline),
                  const SizedBox(height: 12),

                  Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF16161D),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFF2A2A3A)),
                    ),
                    child: Column(
                      children: [
                        _aboutRow(Icons.phone_android, 'The Clozr', 'v${AppConfig.version}'),
                        const Divider(color: Color(0xFF2A2A3A), height: 1),
                        _aboutRow(Icons.security, 'Security', 'Server-side keys, JWT auth'),
                        const Divider(color: Color(0xFF2A2A3A), height: 1),
                        _aboutRow(Icons.business, 'BrandBoost Studio', 'brandbooststudio.co'),
                      ],
                    ),
                  ),

                  // ── Sign Out Button ──
                  if (ref.read(authProvider).isAuthenticated) ...[
                    const SizedBox(height: 32),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: OutlinedButton.icon(
                        onPressed: _logout,
                        icon: const Icon(Icons.logout, color: Color(0xFFFF6B6B)),
                        label: const Text('Sign Out', style: TextStyle(color: Color(0xFFFF6B6B), fontWeight: FontWeight.w600)),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: const Color(0xFFFF6B6B).withOpacity(0.3)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                      ),
                    ),
                  ],

                  const SizedBox(height: 40),
                ],
              ),
            ),
    );
  }

  Widget _sectionHeader(BuildContext context, String title, IconData icon) {
    return Row(
      children: [
        Container(
          width: 32, height: 32,
          decoration: BoxDecoration(
            color: const Color(0xFF6C5CE7).withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 16, color: const Color(0xFF6C5CE7)),
        ),
        const SizedBox(width: 10),
        Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
      ],
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return ListTile(
      leading: Container(
        width: 36, height: 36,
        decoration: BoxDecoration(
          color: const Color(0xFF6C5CE7).withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, size: 16, color: const Color(0xFF6C5CE7)),
      ),
      title: Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
      subtitle: Text(value, style: const TextStyle(fontSize: 12, color: Color(0xFF8B8BA0))),
    );
  }

  Widget _aboutRow(IconData icon, String title, String subtitle) {
    return ListTile(
      leading: Container(
        width: 36, height: 36,
        decoration: BoxDecoration(
          color: const Color(0xFF6C5CE7).withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, size: 16, color: const Color(0xFF6C5CE7)),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 12, color: Color(0xFF8B8BA0))),
    );
  }
}