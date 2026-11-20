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
class RadarController extends ChangeNotifier with WidgetsBindingObserver {
  RadarController(this._service, this._location) {
    WidgetsBinding.instance.addObserver(this);
  }

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
  Future<void> _trackChain = Future<void>.value();
  DateTime? _lastSent;
  bool _trackingBackground = false;
  bool _expiring = false;
  bool _disposed = false;

  String get myId => _service.userId;

  String get activeGroupTitle => groupName ?? 'Sem grupo';

  bool get hasGroup => groupId != null;

  bool get isAdmin =>
      members.where((m) => m.userId == myId).firstOrNull?.role == 'admin';

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
      if (groupId != null) {
        await _loadGroupMeta(groupId!);
        await _service.setPreferredGroupId(groupId!);
        sharing = await _service.mySharing(groupId!);
        await refresh();
      } else {
        groupName = null;
        groupKind = null;
        members = const [];
        sharing = SharingState.off;
        sharingByUser = const {};
        error = null;
        _notify();
      }
    } on Object catch (e) {
      error = 'Não foi possível falar com o Supabase: $e';
      _notify();
    }
    _poll = Timer.periodic(pollInterval, (_) => refresh());
    await _syncTracking();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_disposed) return;
    switch (state) {
      case AppLifecycleState.resumed:
        // Fora da tela o GPS segue enviando; a enquete do mapa volta aqui.
        _poll ??= Timer.periodic(pollInterval, (_) => refresh());
        unawaited(refresh());
        unawaited(_syncTracking());
      case AppLifecycleState.hidden || AppLifecycleState.paused:
        _poll?.cancel();
        _poll = null;
      case AppLifecycleState.inactive || AppLifecycleState.detached:
        break;
    }
  }

  Future<bool> needsAlwaysPermission() => _location.needsAlwaysPermission();

  Future<void> openPermissionSettings() => _location.openPermissionSettings();

  Future<void> retryLocation() async {
    if (locationAccess == LocationAccess.serviceOff) {
      await _location.openLocationSettings();
    }
    await _syncTracking();
  }

  /// Uma troca de modo por vez. A última chamada enxerga o compartilhamento
  /// já atualizado e substitui o fluxo anterior.
  Future<void> _syncTracking() {
    final run = _trackChain.then((_) async {
      if (_disposed) return;
      await _applyTracking();
    });
    _trackChain = run.catchError((Object e) {
      debugPrint('rastreamento: $e');
    });
    return _trackChain;
  }

  Future<void> _applyTracking() async {
    if (_disposed) return;
    final wantBackground = sharing.on && !sharing.expired;
    final access = wantBackground
        ? await _location.ensureBackgroundAccess()
        : await _location.ensureAccess();
    if (_disposed) return;

    locationAccess = access;
    _notify();

    final canTrack =
        access == LocationAccess.granted ||
        access == LocationAccess.backgroundDenied;
    final background = wantBackground && access == LocationAccess.granted;
    if (!canTrack) {
      await _location.setBackgroundActive(false);
      await _positions?.cancel();
      _positions = null;
      _trackingBackground = false;
      return;
    }

    if (_positions != null && _trackingBackground == background) {
      await _location.setBackgroundActive(background);
      return;
    }

    await _positions?.cancel();
    _positions = null;
    if (_disposed) return;

    await _location.setBackgroundActive(background);
    if (_disposed) {
      await _location.setBackgroundActive(false);
      return;
    }

    _trackingBackground = background;
    final last = await _location.lastKnown();
    if (_disposed) return;
    if (last != null) _onPosition(last);

    _positions = _location
        .positions(background: background)
        .listen(
          _onPosition,
          onError: (Object e) => debugPrint('fluxo de localização: $e'),
        );
  }

  void _onPosition(Position p) {
    myPosition = p;
    _notify();
    final hold = _trackingBackground;
    unawaited(_sendFix(hold));
  }

  /// No iPhone, cada leitura ganha uma janela de execução. Sem isso o sistema
  /// suspende o app antes do pedido ao Supabase terminar.
  Future<void> _sendFix(bool hold) async {
    if (hold) await _location.beginUpload();
    try {
      await _maybeSend();
    } finally {
      if (hold) await _location.endUpload();
    }
  }

  Future<void> _maybeSend({bool force = false}) async {
    if (sharing.expired) {
      await _turnOffIfExpired();
      return;
    }
    final p = myPosition;
    if (groupId == null || p == null || !sharing.on) return;
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

  Future<void> _turnOffIfExpired() async {
    final id = groupId;
    if (id == null || _expiring || !sharing.expired || _disposed) return;
    _expiring = true;
    try {
      sharing = await _service.setSharing(id, on: false);
      if (_disposed) return;
      await _syncTracking();
    } on Object catch (e) {
      debugPrint('fim do compartilhamento: $e');
    } finally {
      _expiring = false;
    }
  }

  Future<void> refresh() async {
    final id = groupId;
    if (id == null || _disposed) return;
    try {
      if (sharing.expired) await _turnOffIfExpired();
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
    await _syncTracking();
    await _maybeSend(force: true);
    await refresh();
  }

  Future<void> stopSharing() async {
    final id = groupId;
    if (id == null) return;
    sharing = await _service.setSharing(id, on: false);
    await _syncTracking();
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
    List<String> inviteeIds = const [],
  }) async {
    final group = await _service.createGroup(
      name: name,
      kind: kind,
      inviteeIds: inviteeIds,
    );
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
    WidgetsBinding.instance.removeObserver(this);
    _poll?.cancel();
    unawaited(_positions?.cancel());
    unawaited(_location.setBackgroundActive(false));
    super.dispose();
  }
}
