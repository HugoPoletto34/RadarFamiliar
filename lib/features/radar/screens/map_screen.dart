import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/env.dart';
import '../../../core/di/app_scope.dart';
import '../../../core/location/location_service.dart';
import '../../../core/push/push_service.dart';
import '../../../core/theme/theme.dart';
import '../../friends/screens/add_friend_screen.dart';
import '../../friends/screens/friends_screen.dart';
import '../controllers/radar_controller.dart';
import '../widgets/avatar_style.dart';
import '../widgets/map/google_radar_map.dart';
import '../widgets/map/osm_radar_map.dart';
import '../widgets/map/radar_pin.dart';
import '../widgets/members_panel.dart';
import '../widgets/share_sheet.dart';
import 'group_members_screen.dart';
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
      await _openAddFriend(initialCode: code);
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

  Future<void> _openAddFriend({String? initialCode}) async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => AddFriendScreen(initialCode: initialCode),
      ),
    );
  }

  Future<void> _openFriends() async {
    await Navigator.of(
      context,
    ).push<void>(MaterialPageRoute(builder: (_) => const FriendsScreen()));
  }

  Future<void> _openMembers() async {
    final focus = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => GroupMembersScreen(controller: _controller),
      ),
    );
    if (focus != null) await _focus(focus);
  }

  /// [id] é o `userId` do membro ou `'me'`.
  Future<void> _focus(String id) async {
    final map = _map;
    if (map == null) return;
    if (id == 'me') {
      final me = _controller.myPosition;
      if (me == null) return;
      await map.moveTo(me.latitude, me.longitude, zoom: radarPersonZoom);
      await map.showInfo('me');
      return;
    }
    final f = _controller.friends.where((m) => m.userId == id).firstOrNull;
    if (f == null || !f.hasPosition) return;
    await map.moveTo(f.lat!, f.lng!, zoom: radarPersonZoom);
    await map.showInfo(f.userId);
  }

  Future<void> _openGroups() async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => GroupsScreen(controller: _controller)),
    );
  }

  Future<void> _share() async {
    if (!_controller.hasGroup) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Crie um grupo para compartilhar sua localização.'),
        ),
      );
      await _openGroups();
      return;
    }
    final choice = await showShareSheet(context, _controller.sharing);
    if (choice == null || !mounted) return;
    try {
      if (choice.stop) {
        await _controller.stopSharing();
      } else {
        if (await _controller.needsAlwaysPermission()) {
          if (!mounted) return;
          final go = await confirmBackgroundLocation(context);
          if (!go || !mounted) return;
        }
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

  Future<void> _signOut() async {
    final go = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sair da conta?'),
        content: const Text(
          'Você deixa de ver o grupo neste aparelho até entrar de novo.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sair'),
          ),
        ],
      ),
    );
    if (go == true) await Supabase.instance.client.auth.signOut();
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
    final statusText = !c.hasGroup
        ? 'Crie um grupo para compartilhar'
        : sharingOn
        ? shortSharingLabel(c.sharing)
        : hiddenFriends > 0
        ? 'Compartilhe para ver $hiddenFriends amigo(s)'
        : 'Não compartilhando';

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark.copyWith(
        statusBarColor: Colors.transparent,
      ),
      child: Scaffold(
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
              top: MediaQuery.paddingOf(context).top + AppDimens.spaceSm,
              left: AppDimens.spaceMd,
              right: AppDimens.spaceMd,
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _GroupCard(
                          title: c.activeGroupTitle,
                          status: statusText,
                          on: sharingOn,
                          onTap: _openGroups,
                        ),
                      ),
                      const SizedBox(width: AppDimens.spaceSm),
                      _MapMenu(
                        membersCount: c.friends.length + (c.hasGroup ? 1 : 0),
                        onFriends: _openFriends,
                        onMembers: _openMembers,
                        onSignOut: _signOut,
                      ),
                    ],
                  ),
                  const SizedBox(height: AppDimens.spaceSm),
                  if (c.locationAccess != null &&
                      c.locationAccess != LocationAccess.granted)
                    _Banner(
                      icon: Icons.gps_off,
                      color: scheme.errorContainer,
                      text: switch (c.locationAccess!) {
                        LocationAccess.serviceOff =>
                          'Localização do aparelho desligada.',
                        LocationAccess.backgroundDenied =>
                          'Com o app fechado a posição para. '
                              'Permita localização "Sempre".',
                        LocationAccess.denied || LocationAccess.granted =>
                          'Permissão de localização negada.',
                      },
                      action: TextButton(
                        onPressed:
                            c.locationAccess == LocationAccess.backgroundDenied
                            ? c.openPermissionSettings
                            : c.retryLocation,
                        child: Text(
                          c.locationAccess == LocationAccess.backgroundDenied
                              ? 'Ajustar'
                              : 'Tentar de novo',
                        ),
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
            if (c.hasGroup)
              Positioned(
                left: 16,
                bottom: 96,
                child: MembersPanel(
                  controller: c,
                  onFocus: (id) => unawaited(_focus(id)),
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
          icon: Icon(
            sharingOn ? Icons.share_location : Icons.location_searching,
          ),
          label: Text(sharingOn ? 'Compartilhando' : 'Compartilhar'),
        ),
      ),
    );
  }
}

/// Grupo ativo e status do compartilhamento. Tocar abre a troca de grupo.
class _GroupCard extends StatelessWidget {
  const _GroupCard({
    required this.title,
    required this.status,
    required this.on,
    required this.onTap,
  });

  final String title;
  final String status;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Material(
      color: scheme.surface,
      elevation: 2,
      borderRadius: BorderRadius.circular(AppDimens.radiusLg),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppDimens.spaceSm,
            AppDimens.spaceSm,
            AppDimens.spaceSm + 4,
            AppDimens.spaceSm,
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.accentSoft,
                  borderRadius: BorderRadius.circular(AppDimens.radiusMd),
                ),
                child: const Icon(
                  Icons.groups_rounded,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: AppDimens.spaceSm + 4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: scheme.onSurface,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Icon(
                          Icons.circle,
                          size: 8,
                          color: on ? AppColors.success : scheme.outline,
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            status,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Icon(Icons.unfold_more_rounded, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

enum _MenuAction { friends, members, signOut }

class _MenuRow extends StatelessWidget {
  const _MenuRow({
    required this.icon,
    required this.label,
    this.trailing,
    this.color,
  });

  final IconData icon;
  final String label;
  final String? trailing;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tint = color ?? theme.colorScheme.onSurface;
    final count = trailing;
    return Row(
      children: [
        Icon(icon, size: AppDimens.iconSm, color: tint),
        const SizedBox(width: AppDimens.spaceSm + 4),
        Expanded(
          child: Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: tint,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        if (count != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: AppColors.accentSoft,
              borderRadius: BorderRadius.circular(AppDimens.radiusPill),
            ),
            child: Text(
              count,
              style: theme.textTheme.labelSmall?.copyWith(
                color: AppColors.primary,
              ),
            ),
          ),
      ],
    );
  }
}

/// Ações secundárias do mapa num só botão.
class _MapMenu extends StatelessWidget {
  const _MapMenu({
    required this.membersCount,
    required this.onFriends,
    required this.onMembers,
    required this.onSignOut,
  });

  final int membersCount;
  final VoidCallback onFriends;
  final VoidCallback onMembers;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface,
      elevation: 2,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: PopupMenuButton<_MenuAction>(
        tooltip: 'Menu',
        icon: Icon(Icons.menu_rounded, color: scheme.onSurface),
        iconSize: AppDimens.iconMd,
        padding: const EdgeInsets.all(AppDimens.spaceMd),
        position: PopupMenuPosition.under,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDimens.radiusMd),
        ),
        onSelected: (action) => switch (action) {
          _MenuAction.friends => onFriends(),
          _MenuAction.members => onMembers(),
          _MenuAction.signOut => onSignOut(),
        },
        constraints: const BoxConstraints(minWidth: 240),
        itemBuilder: (context) => [
          const PopupMenuItem(
            value: _MenuAction.friends,
            child: _MenuRow(icon: Icons.person_add_alt_1, label: 'Amigos'),
          ),
          PopupMenuItem(
            value: _MenuAction.members,
            child: _MenuRow(
              icon: Icons.people_alt_outlined,
              label: 'Membros do grupo',
              trailing: membersCount > 0 ? '$membersCount' : null,
            ),
          ),
          const PopupMenuDivider(),
          PopupMenuItem(
            value: _MenuAction.signOut,
            child: _MenuRow(
              icon: Icons.logout,
              label: 'Sair',
              color: scheme.error,
            ),
          ),
        ],
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
