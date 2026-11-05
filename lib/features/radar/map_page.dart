import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config/env.dart';
import '../../core/location/location_service.dart';
import 'avatar_style.dart';
import 'friends_page.dart';
import 'map/google_radar_map.dart';
import 'map/osm_radar_map.dart';
import 'map/radar_pin.dart';
import 'radar_controller.dart';
import 'radar_repository.dart';
import 'share_sheet.dart';

class MapPage extends StatefulWidget {
  const MapPage({super.key});

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  static const _startLat = -23.5505;
  static const _startLng = -46.6333;

  late final RadarController _controller;
  RadarMapHandle? _map;
  bool _centeredOnMe = false;

  @override
  void initState() {
    super.initState();
    _controller = RadarController(
      RadarRepository(Supabase.instance.client),
      LocationService(),
    )..addListener(_onChange);
    unawaited(_controller.start());
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_onChange)
      ..dispose();
    super.dispose();
  }

  void _onChange() {
    final me = _controller.myPosition;
    if (!_centeredOnMe && me != null && _map != null) {
      _centeredOnMe = true;
      unawaited(_map!.moveTo(me.latitude, me.longitude, zoom: 14));
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
            snippet: [
              'visto ${seenAgo(f.lastSeenAt)}',
              if (f.battery != null) 'bateria ${f.battery}%',
            ].join(' · '),
          ),
      if (me != null)
        RadarPin(
          id: 'me',
          label: 'Eu',
          color: meColor,
          lat: me.latitude,
          lng: me.longitude,
          title: 'Você',
          snippet: sharingLabel(c.sharing),
          isMe: true,
        ),
    ];
  }

  Future<void> _openFriends() async {
    final focus = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => FriendsPage(controller: _controller)),
    );
    final f = _controller.friends.where((m) => m.userId == focus).firstOrNull;
    if (f == null || !f.hasPosition || _map == null) return;
    await _map!.moveTo(f.lat!, f.lng!, zoom: 16);
    await _map!.showInfo(f.userId);
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
        title: const Text('Radar Familiar'),
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
            Text(text, style: Theme.of(context).textTheme.labelLarge),
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
