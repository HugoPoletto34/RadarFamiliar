import '../config/env.dart';

/// Deep links de auth e convites (scheme por flavor).
abstract final class AuthRedirect {
  static String get _scheme => Env.isProd
      ? 'br.com.radarfamiliar'
      : 'br.com.radarfamiliar.dev';

  static String get uri => '$_scheme://login-callback';

  static String inviteLink(String code) =>
      '$_scheme://invite?code=${Uri.encodeComponent(code.trim())}';
}

