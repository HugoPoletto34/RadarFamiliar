import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../../core/config/env.dart';
import '../../core/location/location_service.dart';
import 'avatar_style.dart';
import 'member_location.dart';
import 'radar_repository.dart';

/// Estado do protótipo: grupo demo, membros, minha posição e compartilhamento.
class RadarController extends ChangeNotifier {
  RadarController(this._repo, this._location);

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

  final RadarRepository _repo;
  final LocationService _location;

  String? groupId;
  List<MemberLocation> members = const [];
  Position? myPosition;
  SharingState sharing = SharingState.off;
  LocationAccess? locationAccess;
  String? error;

  Timer? _poll;
  StreamSubscription<Position>? _positions;
  DateTime? _lastSent;
  bool _disposed = false;

  String get myId => _repo.userId;

  List<MemberLocation> get friends =>
      members.where((m) => m.userId != myId).toList();

  Color colorOf(String userId) {
    final i = friends.indexWhere((m) => m.userId == userId);
    return friendColor(i < 0 ? 0 : i);
  }

  Future<void> start({String? preferGroupId}) async {
    try {
      groupId = await _repo.resolveActiveGroup(preferGroupId: preferGroupId);
      sharing = await _repo.mySharing(groupId!);
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
      await _repo.sendLocation(
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
        sharing = await _repo.setSharing(id, on: false);
      }
      if (_lastSent == null ||
          DateTime.now().difference(_lastSent!) > _heartbeat) {
        await _maybeSend();
      }
      if (Env.isDev) await _repo.tickFakeFriends(id);
      members = await _repo.groupLocations(id);
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
    sharing = await _repo.setSharing(id, on: true, minutes: minutes);
    _lastSent = null;
    await _maybeSend(force: true);
    await refresh();
  }

  Future<void> stopSharing() async {
    final id = groupId;
    if (id == null) return;
    sharing = await _repo.setSharing(id, on: false);
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
    await _repo.addFakeFriend(id, name);
    await refresh();
  }

  Future<void> useGroup(String id) async {
    groupId = id;
    sharing = await _repo.mySharing(id);
    await refresh();
    _notify();
  }

  Future<void> toggleFakeFriend(String friendId) async {
    final id = groupId;
    if (id == null) return;
    await _repo.toggleFakeFriend(id, friendId);
    await refresh();
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
