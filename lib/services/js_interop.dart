/// Platform-specific JS interop for Clozr.
/// On web, this delegates to js_interop_web.dart which uses dart:js.
/// On mobile, all functions are no-ops.

export 'js_interop_mobile.dart' if (dart.library.html) 'js_interop_web.dart';