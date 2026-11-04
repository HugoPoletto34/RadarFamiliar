/// Configuração injetada em tempo de build via `--dart-define-from-file`.
abstract final class Env {
  static const flavor = String.fromEnvironment('FLAVOR', defaultValue: 'dev');
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabasePublishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
  );

  static bool get isProd => flavor == 'prod';

  static bool get hasSupabase =>
      supabaseUrl.isNotEmpty && supabasePublishableKey.isNotEmpty;
}
