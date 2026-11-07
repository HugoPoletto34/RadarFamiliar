import 'package:supabase_flutter/supabase_flutter.dart';

import 'member_location.dart';

/// Chamadas ao Supabase do radar. As RPCs `dev_*` (amigos simulados)
/// existem só no banco local (supabase/seed.sql).
class RadarRepository {
  RadarRepository(this._client);

  final SupabaseClient _client;

  String get userId => _client.auth.currentUser!.id;

  Future<String> ensureGroup() async =>
      await _client.rpc<String>('proto_ensure_group');

  /// Grupo com mais membros (ex.: após aceitar convite); senão o grupo demo.
  Future<String> resolveActiveGroup({String? preferGroupId}) async {
    if (preferGroupId != null) return preferGroupId;

    final mine = await _client
        .from('group_members')
        .select('group_id')
        .eq('user_id', userId);
    final ids = mine.map((r) => r['group_id'] as String).toList();
    if (ids.isEmpty) return ensureGroup();

    final members = await _client
        .from('group_members')
        .select('group_id')
        .inFilter('group_id', ids);

    var bestId = ids.first;
    var bestCount = 0;
    for (final id in ids) {
      final count = members.where((r) => r['group_id'] == id).length;
      if (count > bestCount) {
        bestCount = count;
        bestId = id;
      }
    }
    if (bestCount > 1) return bestId;
    return ensureGroup();
  }

  Future<List<MemberLocation>> groupLocations(String groupId) async {
    final rows = await _client.rpc<List<dynamic>>(
      'get_group_locations',
      params: {'p_group_id': groupId},
    );
    return rows
        .cast<Map<String, dynamic>>()
        .map(MemberLocation.fromRow)
        .toList();
  }

  Future<SharingState> mySharing(String groupId) async {
    final row = await _client
        .from('sharing_settings')
        .select('mode, temporary_until')
        .eq('group_id', groupId)
        .eq('user_id', userId)
        .maybeSingle();
    if (row == null || row['mode'] == 'off') return SharingState.off;
    final until = DateTime.tryParse(
      (row['temporary_until'] as String?) ?? '',
    )?.toLocal();
    return SharingState(on: true, until: until);
  }

  /// [minutes] nulo = até desligar.
  Future<SharingState> setSharing(
    String groupId, {
    required bool on,
    int? minutes,
  }) async {
    final until = await _client.rpc<String?>(
      'proto_set_sharing',
      params: {'p_group_id': groupId, 'p_on': on, 'p_minutes': minutes},
    );
    if (!on) return SharingState.off;
    return SharingState(
      on: true,
      until: until == null ? null : DateTime.parse(until).toLocal(),
    );
  }

  Future<bool> sendLocation({
    required double lat,
    required double lng,
    double? accuracy,
    double? speed,
    DateTime? recordedAt,
  }) async {
    final result = await _client.rpc<Map<String, dynamic>>(
      'ingest_location',
      params: {
        'p_lat': lat,
        'p_lng': lng,
        'p_accuracy_m': accuracy,
        'p_speed': speed,
        'p_recorded_at': recordedAt?.toUtc().toIso8601String(),
      },
    );
    return result['accepted'] == true;
  }

  Future<void> addFakeFriend(String groupId, String name) => _client.rpc<void>(
    'dev_add_fake_friend',
    params: {'p_group_id': groupId, 'p_name': name},
  );

  Future<void> tickFakeFriends(String groupId) => _client.rpc<void>(
    'dev_tick_fake_friends',
    params: {'p_group_id': groupId},
  );

  Future<void> toggleFakeFriend(String groupId, String friendId) =>
      _client.rpc<void>(
        'dev_toggle_fake_friend',
        params: {'p_group_id': groupId, 'p_user_id': friendId},
      );
}
