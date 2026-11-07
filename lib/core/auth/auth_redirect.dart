import '../config/env.dart';

/// URL de retorno do OAuth (Google) após login no navegador in-app.
abstract final class AuthRedirect {
  static String get uri => Env.isProd
      ? 'br.com.radarfamiliar://login-callback'
      : 'br.com.radarfamiliar.dev://login-callback';
}
