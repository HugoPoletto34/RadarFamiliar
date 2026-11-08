/// Lê o código de `scheme://invite/CODE` ou do formato antigo `?code=`.
String? inviteCodeFromUri(Uri uri) {
  if (uri.host != 'invite') return null;
  final fromQuery = uri.queryParameters['code'];
  final raw = (fromQuery != null && fromQuery.trim().isNotEmpty)
      ? fromQuery
      : (uri.pathSegments.isNotEmpty ? uri.pathSegments.first : null);
  if (raw == null || raw.trim().isEmpty) return null;
  return raw.trim().toUpperCase();
}
