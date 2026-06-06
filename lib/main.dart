import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'screens/home_screen.dart';
import 'screens/meeting_screen.dart';
import 'screens/proposal_screen.dart';
import 'screens/proposal_view_screen.dart';
import 'screens/followup_email_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/catalog_screen.dart';
import 'screens/login_screen.dart';
import 'screens/pricing_screen.dart';
import 'services/auth_service.dart';
import 'services/app_config.dart';

/// Auth provider — shared across all screens
final authProvider = StateNotifierProvider<AuthNotifier, AuthService>((ref) {
  return AuthNotifier(AuthService());
});

class AuthNotifier extends StateNotifier<AuthService> {
  AuthNotifier(AuthService auth) : super(auth) {
    _init();
  }

  Future<void> _init() async {
    await state.loadFromStorage();
    // Notify listeners that auth state may have changed
    state = state;
  }
}

final router = GoRouter(
  redirect: (context, state) {
    // All routes accessible — auth check happens in-screen via authProvider
    return null;
  },
  routes: [
    GoRoute(path: '/', builder: (context, state) => const HomeScreen()),
    GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
    GoRoute(path: '/meeting', builder: (context, state) => const MeetingScreen()),
    GoRoute(path: '/meeting/:id', builder: (context, state) {
      final meetingId = state.pathParameters['id']!;
      return MeetingScreen(meetingId: meetingId);
    }),
    GoRoute(path: '/proposal/:id', builder: (context, state) {
      final meetingId = state.pathParameters['id']!;
      return ProposalScreen(meetingId: meetingId);
    }),
    GoRoute(path: '/proposal/view/:proposalId', builder: (context, state) {
      final proposalId = state.pathParameters['proposalId']!;
      return ProposalViewScreen(proposalId: proposalId);
    }),
    GoRoute(path: '/settings', builder: (context, state) => const SettingsScreen()),
    GoRoute(path: '/followup', builder: (context, state) {
      final meetingId = state.uri.queryParameters['meetingId'] ?? '';
      return FollowUpEmailScreen(meetingId: meetingId);
    }),
    GoRoute(path: '/catalog', builder: (context, state) => const CatalogScreen()),
    GoRoute(path: '/pricing', builder: (context, state) => const PricingScreen()),
  ],
);

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: ClozrApp()));
}

class ClozrApp extends StatelessWidget {
  const ClozrApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'The Clozr',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0D0D12),
        colorScheme: ColorScheme.dark(
          primary: const Color(0xFF6C5CE7),
          primaryContainer: const Color(0xFF6C5CE7).withValues(alpha: 0.15),
          secondary: const Color(0xFF00D2D3),
          secondaryContainer: const Color(0xFF00D2D3).withValues(alpha: 0.15),
          surface: const Color(0xFF16161D),
          surfaceContainerHighest: const Color(0xFF1E1E28),
          onSurface: const Color(0xFFE8E8F0),
          onSurfaceVariant: const Color(0xFF8B8BA0),
          outline: const Color(0xFF2A2A3A),
          error: const Color(0xFFFF6B6B),
          onError: Colors.white,
        ),
        cardTheme: CardThemeData(
          color: const Color(0xFF16161D),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Color(0xFF2A2A3A)),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF6C5CE7),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF0D0D12),
          elevation: 0,
          centerTitle: false,
          titleTextStyle: TextStyle(
            color: Color(0xFFE8E8F0),
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
        ),
        tabBarTheme: TabBarThemeData(
          labelColor: const Color(0xFF6C5CE7),
          unselectedLabelColor: const Color(0xFF8B8BA0),
          indicatorColor: const Color(0xFF6C5CE7),
          indicatorSize: TabBarIndicatorSize.label,
          labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          unselectedLabelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
        ),
        useMaterial3: true,
      ),
      routerConfig: router,
    );
  }
}