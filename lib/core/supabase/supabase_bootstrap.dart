import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/env.dart';

/// Guarda a sessão no Keystore/Keychain para que o callback headless de
/// cercas (outro isolate) consiga reabrir a sessão no Marco 1.
class SecureLocalStorage extends LocalStorage {
  SecureLocalStorage();

  static const _key = 'supabase.session';
  static const _storage = FlutterSecureStorage();

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> hasAccessToken() => _storage.containsKey(key: _key);

  @override
  Future<String?> accessToken() => _storage.read(key: _key);

  @override
  Future<void> persistSession(String persistSessionString) =>
      _storage.write(key: _key, value: persistSessionString);

  @override
  Future<void> removePersistedSession() => _storage.delete(key: _key);
}

Future<void> initSupabase() async {
  if (!Env.hasSupabase) {
    throw StateError(
      'SUPABASE_URL e SUPABASE_PUBLISHABLE_KEY ausentes. '
      'Rode com --dart-define-from-file=env/${Env.flavor}.json',
    );
  }
  await Supabase.initialize(
    url: Env.supabaseUrl,
    publishableKey: Env.supabasePublishableKey,
    authOptions: FlutterAuthClientOptions(localStorage: SecureLocalStorage()),
  );
}
