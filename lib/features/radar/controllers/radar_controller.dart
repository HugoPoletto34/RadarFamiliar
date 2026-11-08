import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../../../core/config/env.dart';
import '../../../core/location/location_service.dart';
import '../models/member_location.dart';
import '../models/radar_group.dart';
import '../services/radar_service.dart';
import '../widgets/avatar_style.dart';

/// Estado do radar: grupo ativo, membros, posição e compartilhamento.
class RadarController extends ChangeNotifier {
  RadarController(this._service, this._location);

  static const pollInterval = Duration(seconds: 5);
  static const _minSendInterval = Duration(seconds: 20);
  static const _heartbeat = Duration(seconds: 30);
  static const _fakeNames = [
    'Ana',
    'Bruno',
    'Carla',
    'Diego',
    'Elisa',
    'Fábio',
    'Gabi',
    'Heitor',
  ];

  final RadarService _service;
  final LocationService _location;

  String? groupId;
  String? groupName;
  GroupKind? groupKind;
  List<MemberLocation> members = const [];
  Position? myPosition;
  SharingState sharing = SharingState.off;
  Map<String, SharingState> sharingByUser = const {};
  LocationAccess? locationAccess;
  String? error;

  Timer? _poll;
  StreamSubscription<Position>? _positions;
  DateTime? _lastSent;
  bool _disposed = false;

  String get myId => _service.userId;

  String get activeGroupTitle => groupName ?? 'Amigos';

  List<MemberLocation> get friends =>
      members.where((m) => m.userId != myId).toList();

  String get myName =>
      members.where((m) => m.userId == myId).firstOrNull?.name ?? 'Você';

  SharingState sharingOf(String userId) =>
      userId == myId ? sharing : (sharingByUser[userId] ?? SharingState.off);

  Color colorOf(String userId) {
    final i = friends.indexWhere((m) => m.userId == userId);
    return friendColor(i < 0 ? 0 : i);
  }

  Future<void> start({String? preferGroupId}) async {
    try {
      groupId = await _service.resolveActiveGroup(preferGroupId: preferGroupId);
      await _loadGroupMeta(groupId!);
      await _service.setPreferredGroupId(groupId!);
      sharing = await _service.mySharing(groupId!);
      await refresh();
    } on Object catch (e) {
      error = 'Não foi possível falar com o Supabase: $e';
      _notify();
    }
    _poll = Timer.periodic(pollInterval, (_) => refresh());
    await _startLocation();
  }

  Future<void> _startLocation() async {
    locationAccess = await _location.ensureAccess();
    _notify();
    if (locationAccess != LocationAccess.granted) return;
    final last = await _location.lastKnown();
    if (last != null) _onPosition(last);
    _positions = _location.positions().listen(_onPosition);
  }

  Future<void> retryLocation() async {
    await _positions?.cancel();
    await _startLocation();
  }

  void _onPosition(Position p) {
    myPosition = p;
    _notify();
    unawaited(_maybeSend());
  }

  Future<void> _maybeSend({bool force = false}) async {
    final p = myPosition;
    if (groupId == null || p == null || !sharing.on || sharing.expired) return;
    final now = DateTime.now();
    if (!force &&
        _lastSent != null &&
        now.difference(_lastSent!) < _minSendInterval) {
      return;
    }
    _lastSent = now;
    try {
      await _service.sendLocation(
        lat: p.latitude,
        lng: p.longitude,
        accuracy: p.accuracy,
        speed: p.speed,
        // Horário do envio, não da leitura do GPS: parado, o heartbeat reenvia a
        // mesma leitura e o servidor recusaria como "stale".
        recordedAt: now,
      );
    } on Object catch (e) {
      debugPrint('ingest_location falhou: $e');
    }
  }

  Future<void> refresh() async {
    final id = groupId;
    if (id == null || _disposed) return;
    try {
      if (sharing.expired) {
        sharing = await _service.setSharing(id, on: false);
      }
      if (_lastSent == null ||
          DateTime.now().difference(_lastSent!) > _heartbeat) {
        await _maybeSend();
      }
      if (Env.isDev) await _service.tickFakeFriends(id);
      final locations = await _service.groupLocations(id);
      final windows = await _service.groupSharing(id);
      members = locations;
      sharingByUser = windows;
      error = null;
    } on Object catch (e) {
      error = 'Falha ao atualizar: $e';
    }
    _notify();
  }

  /// [minutes] nulo = até desligar.
  Future<void> startSharing({int? minutes}) async {
    final id = groupId;
    if (id == null) return;
    sharing = await _service.setSharing(id, on: true, minutes: minutes);
    _lastSent = null;
    await _maybeSend(force: true);
    await refresh();
  }

  Future<void> stopSharing() async {
    final id = groupId;
    if (id == null) return;
    sharing = await _service.setSharing(id, on: false);
    await refresh();
  }

  Future<void> addFakeFriend() async {
    final id = groupId;
    if (id == null) return;
    final used = members.map((m) => m.name).toSet();
    final name = _fakeNames.firstWhere(
      (n) => !used.contains(n),
      orElse: () => 'Amigo ${members.length}',
    );
    await _service.addFakeFriend(id, name);
    await refresh();
  }

  Future<void> useGroup(String id) async {
    groupId = id;
    await _loadGroupMeta(id);
    await _service.setPreferredGroupId(id);
    sharing = await _service.mySharing(id);
    await refresh();
    _notify();
  }

  Future<RadarGroup> createGroup({
    required String name,
    required GroupKind kind,
  }) async {
    final group = await _service.createGroup(name: name, kind: kind);
    await useGroup(group.id);
    return group;
  }

  Future<List<RadarGroup>> listGroups() => _service.myGroups();

  Future<void> toggleFakeFriend(String friendId) async {
    final id = groupId;
    if (id == null) return;
    await _service.toggleFakeFriend(id, friendId);
    await refresh();
  }

  Future<void> _loadGroupMeta(String id) async {
    final group = await _service.groupById(id);
    groupName = group?.name;
    groupKind = group?.kind;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _poll?.cancel();
    unawaited(_positions?.cancel());
    super.dispose();
  }
}
