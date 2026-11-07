/// Lê o código de convite de um deep link `scheme://invite?code=...`.
String? inviteCodeFromUri(Uri uri) {
  if (uri.host != 'invite') return null;
  final raw = uri.queryParameters['code'];
  if (raw == null || raw.trim().isEmpty) return null;
  return raw.trim().toUpperCase();
}
