import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/invite_preview.dart';

class InviteService {
  InviteService(this._client);

  final SupabaseClient _client;

  String get userId => _client.auth.currentUser!.id;

  Future<CreatedInvite> createInvite(String groupId) async {
    final rows = await _client.rpc<List<dynamic>>(
      'create_invite',
      params: {'p_group_id': groupId},
    );
    return CreatedInvite.fromRow(rows.first as Map<String, dynamic>);
  }

  Future<InvitePreview> previewInvite(String code) async {
    final rows = await _client.rpc<List<dynamic>>(
      'preview_invite',
      params: {'p_code': code},
    );
    if (rows.isEmpty) {
      throw const InviteException('Convite inválido ou expirado.');
    }
    return InvitePreview.fromRow(rows.first as Map<String, dynamic>);
  }

  Future<String> acceptInvite(String code) async {
    return await _client.rpc<String>('accept_invite', params: {'p_code': code});
  }

  Future<void> ensureBirthDate(DateTime birthDate) async {
    final day = DateTime(birthDate.year, birthDate.month, birthDate.day);
    await _client
        .from('profiles')
        .update({'birth_date': day.toIso8601String().split('T').first})
        .eq('id', userId);
  }

  Future<DateTime?> birthDate() async {
    final row = await _client
        .from('profiles')
        .select('birth_date')
        .eq('id', userId)
        .maybeSingle();
    if (row == null || row['birth_date'] == null) return null;
    return DateTime.parse(row['birth_date'] as String);
  }
}

class InviteException implements Exception {
  const InviteException(this.message);
  final String message;

  @override
  String toString() => message;
}

String inviteErrorMessage(Object error) {
  if (error is InviteException) return error.message;
  if (error is PostgrestException) {
    final msg = error.message.toLowerCase();
    if (msg.contains('invalid_invite') || msg.contains('p0002')) {
      return 'Convite inválido, expirado ou já usado.';
    }
    if (msg.contains('birth_date_required') || msg.contains('underage')) {
      return 'Informe sua data de nascimento (maior de 18 anos) para entrar.';
    }
    if (msg.contains('not_authenticated')) {
      return 'Entre na sua conta para aceitar o convite.';
    }
    return error.message;
  }
  if (error is AuthException) return error.message;
  return '$error';
}
