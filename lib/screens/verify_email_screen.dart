import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../main.dart';

class VerifyEmailScreen extends ConsumerStatefulWidget {
  final String? token;

  const VerifyEmailScreen({super.key, this.token});

  @override
  ConsumerState<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends ConsumerState<VerifyEmailScreen> {
  bool _isLoading = true;
  bool _verified = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _verifyEmail();
  }

  Future<void> _verifyEmail() async {
    final token = widget.token;
    if (token == null || token.isEmpty) {
      setState(() {
        _isLoading = false;
        _error = 'No verification token found. Check your email for the correct link.';
      });
      return;
    }

    final auth = ref.read(authProvider);
    final success = await auth.verifyEmail(token: token);

    if (!mounted) return;

    setState(() {
      _isLoading = false;
      _verified = success;
      if (!success) {
        _error = 'Verification failed. The link may have expired. Please request a new verification email.';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D12),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_isLoading) ...[
                  const Center(
                    child: Column(
                      children: [
                        CircularProgressIndicator(color: Color(0xFF6C5CE7), strokeWidth: 3),
                        SizedBox(height: 20),
                        Text(
                          'Verifying your email...',
                          style: TextStyle(fontSize: 18, color: Color(0xFFE8E8F0)),
                        ),
                      ],
                    ),
                  ),
                ] else if (_verified) ...[
                  const Icon(
                    Icons.verified_outlined,
                    size: 64,
                    color: Color(0xFF00D2D3),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Email Verified!',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFFE8E8F0),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Your email has been verified successfully. You can now use all features of The Clozr.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14, color: Color(0xFF8B8BA0)),
                  ),
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: FilledButton.icon(
                      onPressed: () => context.go('/login'),
                      icon: const Icon(Icons.login_rounded, size: 22),
                      label: const Text('Continue to Sign In', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF6C5CE7),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                    ),
                  ),
                ] else ...[
                  const Icon(
                    Icons.error_outline,
                    size: 64,
                    color: Color(0xFFFF6B6B),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Verification Failed',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFFE8E8F0),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _error ?? 'Something went wrong.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 14, color: Color(0xFF8B8BA0)),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: FilledButton.icon(
                      onPressed: () => context.go('/login'),
                      icon: const Icon(Icons.login_rounded, size: 22),
                      label: const Text('Back to Sign In', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF6C5CE7),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}