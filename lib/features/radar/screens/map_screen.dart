import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/env.dart';
import '../../../core/di/app_scope.dart';
import '../../../core/location/location_service.dart';
import '../../../core/push/push_service.dart';
import '../../invites/screens/join_invite_screen.dart';
import '../controllers/radar_controller.dart';
import '../widgets/avatar_style.dart';
import '../widgets/map/google_radar_map.dart';
import '../widgets/map/osm_radar_map.dart';
import '../widgets/map/radar_pin.dart';
import '../widgets/share_sheet.dart';
import 'friends_screen.dart';
import 'groups_screen.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({
    super.key,
    this.pendingInviteCode,
    this.onConsumedPendingInvite,
  });

  final String? pendingInviteCode;
  final VoidCallback? onConsumedPendingInvite;

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  static const _startLat = -23.5505;
  static const _startLng = -46.6333;

  late final RadarController _controller;
  RadarMapHandle? _map;
  bool _centeredOnMe = false;
  bool _wired = false;
  bool _mapReady = false;
  String? _groupFromPush;
  StreamSubscription<PushOpen>? _pushSub;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_wired) return;
    _wired = true;
    final scope = AppScope.of(context);
    _controller = RadarController(scope.radarService, scope.locationService)
      ..addListener(_onChange);
    final push = scope.pushService;
    final opened = push?.takePending();
    _pushSub = push?.opens.listen(_onPushOpen);
    _groupFromPush = push?.takePending()?.groupId ?? opened?.groupId;
    unawaited(_boot());
  }

  void _onPushOpen(PushOpen open) {
    final groupId = open.groupId;
    if (groupId == null) return;
    _groupFromPush = groupId;
    if (_mapReady) unawaited(_controller.useGroup(groupId));
  }

  Future<void> _boot() async {
    await _controller.start(preferGroupId: _groupFromPush);
    _mapReady = true;
    final queued = _groupFromPush;
    if (queued != null && queued != _controller.groupId) {
      await _controller.useGroup(queued);
    }
    final code = widget.pendingInviteCode;
    if (code != null && mounted) {
      widget.onConsumedPendingInvite?.call();
      await _openJoinInvite(initialCode: code);
    }
  }

  @override
  void dispose() {
    unawaited(_pushSub?.cancel());
    if (_wired) {
      _controller
        ..removeListener(_onChange)
        ..dispose();
    }
    super.dispose();
  }

  void _onChange() {
    final me = _controller.myPosition;
    if (!_centeredOnMe && me != null && _map != null) {
      _centeredOnMe = true;
      unawaited(_map!.moveTo(me.latitude, me.longitude, zoom: radarPersonZoom));
    }
    setState(() {});
  }

  List<RadarPin> _pins() {
    final c = _controller;
    final me = c.myPosition;
    return [
      for (final f in c.friends)
        if (f.isSharing && f.hasPosition)
          RadarPin(
            id: f.userId,
            label: f.initial,
            color: c.colorOf(f.userId),
            lat: f.lat!,
            lng: f.lng!,
            title: f.name,
            snippet: sharingDurationLabel(c.sharingOf(f.userId)),
          ),
      if (me != null)
        RadarPin(
          id: 'me',
          label: 'Eu',
          color: meColor,
          lat: me.latitude,
          lng: me.longitude,
          title: c.myName,
          snippet: sharingDurationLabel(c.sharing),
          isMe: true,
        ),
    ];
  }

  Future<void> _openJoinInvite({String? initialCode}) async {
    final groupId = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => JoinInviteScreen(initialCode: initialCode),
      ),
    );
    if (groupId != null) await _controller.useGroup(groupId);
  }

  Future<void> _openFriends() async {
    final focus = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => FriendsScreen(controller: _controller)),
    );
    final f = _controller.friends.where((m) => m.userId == focus).firstOrNull;
    if (f == null || !f.hasPosition || _map == null) return;
    await _map!.moveTo(f.lat!, f.lng!, zoom: radarPersonZoom);
    await _map!.showInfo(f.userId);
  }

  Future<void> _openGroups() async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => GroupsScreen(controller: _controller)),
    );
  }

  Future<void> _share() async {
    final choice = await showShareSheet(context, _controller.sharing);
    if (choice == null) return;
    try {
      if (choice.stop) {
        await _controller.stopSharing();
      } else {
        await _controller.startSharing(minutes: choice.minutes);
      }
    } on Object catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  void _onMapReady(RadarMapHandle handle) {
    _map = handle;
    _onChange();
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    final sharingOn = c.sharing.on && !c.sharing.expired;
    final pins = _pins();
    final hiddenFriends = c.friends
        .where((f) => f.isSharing && !f.hasPosition)
        .length;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: InkWell(
          onTap: _openGroups,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    c.activeGroupTitle,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const Icon(Icons.arrow_drop_down),
              ],
            ),
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Amigos',
            onPressed: _openFriends,
            icon: Badge.count(
              count: c.friends.length,
              isLabelVisible: c.friends.isNotEmpty,
              child: const Icon(Icons.people_alt_outlined),
            ),
          ),
          IconButton(
            tooltip: 'Sair',
            icon: const Icon(Icons.logout),
            onPressed: () => Supabase.instance.client.auth.signOut(),
          ),
        ],
      ),
      body: Stack(
        children: [
          if (Env.hasGoogleMaps)
            GoogleRadarMap(
              pins: pins,
              initialLat: _startLat,
              initialLng: _startLng,
              onReady: _onMapReady,
            )
          else
            OsmRadarMap(
              pins: pins,
              initialLat: _startLat,
              initialLng: _startLng,
              onReady: _onMapReady,
            ),
          Positioned(
            top: 12,
            left: 12,
            right: 12,
            child: Column(
              children: [
                _StatusPill(
                  on: sharingOn,
                  text: sharingOn
                      ? shortSharingLabel(c.sharing)
                      : hiddenFriends > 0
                      ? 'Compartilhe para ver $hiddenFriends amigo(s)'
                      : 'Não compartilhando',
                ),
                if (c.locationAccess != null &&
                    c.locationAccess != LocationAccess.granted)
                  _Banner(
                    icon: Icons.gps_off,
                    color: scheme.errorContainer,
                    text: c.locationAccess == LocationAccess.serviceOff
                        ? 'Localização do aparelho desligada.'
                        : 'Permissão de localização negada.',
                    action: TextButton(
                      onPressed: c.retryLocation,
                      child: const Text('Tentar de novo'),
                    ),
                  ),
                if (c.error != null)
                  _Banner(
                    icon: Icons.cloud_off,
                    color: scheme.errorContainer,
                    text: c.error!,
                  ),
              ],
            ),
          ),
          Positioned(
            right: 16,
            bottom: 96,
            child: FloatingActionButton.small(
              heroTag: 'fit',
              tooltip: 'Mostrar todos',
              onPressed: () => _map?.fit(pins),
              child: const Icon(Icons.center_focus_strong),
            ),
          ),
        ],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'share',
        onPressed: _share,
        backgroundColor: sharingOn ? scheme.primary : null,
        foregroundColor: sharingOn ? scheme.onPrimary : null,
        icon: Icon(sharingOn ? Icons.share_location : Icons.location_searching),
        label: Text(sharingOn ? 'Compartilhando' : 'Compartilhar'),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.on, required this.text});

  final bool on;
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface.withValues(alpha: 0.92),
      shape: const StadiumBorder(),
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.circle,
              size: 10,
              color: on ? scheme.primary : scheme.outline,
            ),
            const SizedBox(width: 8),
            Text(
              text,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({
    required this.icon,
    required this.color,
    required this.text,
    this.action,
  });

  final IconData icon;
  final Color color;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: color,
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Icon(icon, size: 20),
            const SizedBox(width: 10),
            Expanded(child: Text(text)),
            ?action,
          ],
        ),
      ),
    );
  }
}
