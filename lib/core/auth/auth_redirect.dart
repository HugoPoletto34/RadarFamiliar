import '../config/env.dart';

/// Deep links de auth e convites (scheme por flavor).
abstract final class AuthRedirect {
  static String get _scheme =>
      Env.isProd ? 'br.com.radarfamiliar' : 'br.com.radarfamiliar.dev';

  static String get uri => '$_scheme://login-callback';

  /// Scheme sem pontos. `br.com.radarfamiliar.dev://...` parece um site
  /// (TLD `.dev`) e o WhatsApp corta o link antes do código.
  static String get _inviteScheme =>
      Env.isProd ? 'radarfamiliar' : 'radarfamiliar-dev';

  static String inviteLink(String code) {
    final normalized = code.trim().toUpperCase();
    return '$_inviteScheme://invite/$normalized';
  }
}
