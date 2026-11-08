import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/member_location.dart';
import '../models/radar_group.dart';

/// Chamadas ao Supabase do radar. As RPCs `dev_*` (amigos simulados)
/// existem só no banco local (supabase/seed.sql).
class RadarService {
  RadarService(this._client);

  static const _activeGroupKey = 'active_group_id';

  final SupabaseClient _client;

  String get userId => _client.auth.currentUser!.id;

  Future<String> ensureGroup() async =>
      await _client.rpc<String>('proto_ensure_group');

  Future<String?> preferredGroupId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_activeGroupKey);
  }

  Future<void> setPreferredGroupId(String groupId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_activeGroupKey, groupId);
  }

  /// Preferência do aparelho, senão o grupo com mais membros; senão o demo.
  Future<String> resolveActiveGroup({String? preferGroupId}) async {
    if (preferGroupId != null) return preferGroupId;

    final mine = await _client
        .from('group_members')
        .select('group_id')
        .eq('user_id', userId);
    final ids = mine.map((r) => r['group_id'] as String).toList();
    if (ids.isEmpty) return ensureGroup();

    final saved = await preferredGroupId();
    if (saved != null && ids.contains(saved)) return saved;

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

  Future<List<RadarGroup>> myGroups() async {
    final rows = await _client
        .from('group_members')
        .select('groups(id, name, kind)')
        .eq('user_id', userId);
    final groups = <RadarGroup>[];
    for (final row in rows) {
      final raw = row['groups'];
      if (raw is Map<String, dynamic>) {
        groups.add(RadarGroup.fromRow(raw));
      }
    }
    groups.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return groups;
  }

  Future<RadarGroup?> groupById(String groupId) async {
    final row = await _client
        .from('groups')
        .select('id, name, kind')
        .eq('id', groupId)
        .maybeSingle();
    if (row == null) return null;
    return RadarGroup.fromRow(row);
  }

  Future<RadarGroup> createGroup({
    required String name,
    required GroupKind kind,
  }) async {
    final error = RadarGroup.validateName(name);
    if (error != null) throw ArgumentError(error);

    final id = await _client.rpc<String>(
      'create_group',
      params: {'p_name': name.trim(), 'p_kind': kind.apiValue},
    );
    return RadarGroup(id: id, name: name.trim(), kind: kind);
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
    return sharingStateFromRow(row);
  }

  /// Modo e prazo de cada membro do grupo. A RLS deixa o membro ler isso.
  Future<Map<String, SharingState>> groupSharing(String groupId) async {
    final rows = await _client
        .from('sharing_settings')
        .select('user_id, mode, temporary_until')
        .eq('group_id', groupId);
    return {
      for (final row in rows)
        row['user_id'] as String: sharingStateFromRow(row),
    };
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
