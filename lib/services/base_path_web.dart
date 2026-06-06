/// Runtime base path detection for Flutter web.
/// Uses window.location.pathname to determine if the app
/// is deployed at a subpath (e.g., /clozr/) or at root (/).
///
/// A single build works at both:
/// - http://localhost:8510/ (root deployment)
/// - https://domain/clozr/ (subpath deployment via Tailscale Funnel)

import 'dart:js' as js;

String detectBasePath() {
  try {
    final pathname = js.context['window']['location']['pathname'] as String?;
    if (pathname != null && pathname.startsWith('/clozr')) {
      return '/clozr';
    }
    return '';
  } catch (_) {
    return '';
  }
}