import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/friend.dart';

class FriendService {
  FriendService(this._client);

  final SupabaseClient _client;

  String get userId => _client.auth.currentUser!.id;

  Future<String> myFriendCode() async =>
      await _client.rpc<String>('my_friend_code');

  Future<String> regenerateFriendCode() async =>
      await _client.rpc<String>('regenerate_friend_code');

  Future<FriendPreview> previewFriendCode(String code) async {
    final rows = await _client.rpc<List<dynamic>>(
      'preview_friend_code',
      params: {'p_code': code},
    );
    if (rows.isEmpty) {
      throw const FriendException('Código inválido.');
    }
    return FriendPreview.fromRow(rows.first as Map<String, dynamic>);
  }

  /// Devolve `'pending'` ou `'accepted'`.
  Future<String> requestFriend(String code) async =>
      await _client.rpc<String>('request_friend', params: {'p_code': code});

  Future<void> respondFriendRequest(
    String requesterId, {
    required bool accept,
  }) => _client.rpc<void>(
    'respond_friend_request',
    params: {'p_requester_id': requesterId, 'p_accept': accept},
  );

  Future<void> cancelFriendRequest(String addresseeId) => _client.rpc<void>(
    'cancel_friend_request',
    params: {'p_addressee_id': addresseeId},
  );

  Future<void> removeFriend(String userId) =>
      _client.rpc<void>('remove_friend', params: {'p_user_id': userId});

  Future<FriendsList> listFriends() async {
    final rows = await _client.rpc<List<dynamic>>('list_friends');
    final friends = <Friend>[];
    final incoming = <FriendRequest>[];
    final outgoing = <FriendRequest>[];
    for (final raw in rows) {
      final row = raw as Map<String, dynamic>;
      switch (row['kind'] as String) {
        case 'friend':
          friends.add(Friend.fromRow(row));
        case 'incoming':
          incoming.add(FriendRequest.fromRow(row));
        case 'outgoing':
          outgoing.add(FriendRequest.fromRow(row));
      }
    }
    return FriendsList(
      friends: friends,
      incoming: incoming,
      outgoing: outgoing,
    );
  }

  Future<int> inviteToGroup(String groupId, List<String> userIds) async {
    final count = await _client.rpc<int>(
      'invite_to_group',
      params: {'p_group_id': groupId, 'p_user_ids': userIds},
    );
    return count;
  }

  Future<void> cancelGroupInvite(String groupId, String userId) =>
      _client.rpc<void>(
        'cancel_group_invite',
        params: {'p_group_id': groupId, 'p_user_id': userId},
      );

  Future<String?> respondGroupInvite(String groupId, {required bool accept}) =>
      _client.rpc<String?>(
        'respond_group_invite',
        params: {'p_group_id': groupId, 'p_accept': accept},
      );

  Future<List<GroupInvite>> myGroupInvites() async {
    final rows = await _client.rpc<List<dynamic>>('my_group_invites');
    return rows.cast<Map<String, dynamic>>().map(GroupInvite.fromRow).toList();
  }

  Future<List<PendingGroupInvite>> listGroupPendingInvites(
    String groupId,
  ) async {
    final rows = await _client.rpc<List<dynamic>>(
      'list_group_pending_invites',
      params: {'p_group_id': groupId},
    );
    return rows
        .cast<Map<String, dynamic>>()
        .map(PendingGroupInvite.fromRow)
        .toList();
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

class FriendException implements Exception {
  const FriendException(this.message);
  final String message;

  @override
  String toString() => message;
}

String friendErrorMessage(Object error) {
  if (error is FriendException) return error.message;
  if (error is PostgrestException) {
    final msg = error.message.toLowerCase();
    if (msg.contains('birth_date_required') || msg.contains('underage')) {
      return 'Informe sua data de nascimento (maior de 18 anos) para continuar.';
    }
    if (msg.contains('cannot_friend_self')) {
      return 'Esse código é o seu.';
    }
    if (msg.contains('already_friends')) {
      return 'Vocês já são amigos.';
    }
    if (msg.contains('already_pending')) {
      return 'Pedido já enviado. Aguarde a resposta.';
    }
    if (msg.contains('not_friends')) {
      return 'Só é possível convidar quem já é seu amigo.';
    }
    if (msg.contains('not_admin')) {
      return 'Só o administrador do grupo pode convidar.';
    }
    if (msg.contains('request_not_found') ||
        msg.contains('invite_not_found') ||
        msg.contains('friend_not_found')) {
      return 'Pedido ou convite não encontrado.';
    }
    if (msg.contains('invalid_code')) {
      return 'Código inválido.';
    }
    if (msg.contains('not_authenticated')) {
      return 'Entre na sua conta para continuar.';
    }
    return error.message;
  }
  if (error is AuthException) return error.message;
  return '$error';
}
