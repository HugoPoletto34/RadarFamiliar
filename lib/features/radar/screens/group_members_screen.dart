import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/config/env.dart';
import '../../../core/di/app_scope.dart';
import '../../../core/theme/app_dimens.dart';
import '../../friends/models/friend.dart';
import '../../friends/services/friend_service.dart';
import '../controllers/radar_controller.dart';
import '../models/member_location.dart';
import '../widgets/share_sheet.dart';

/// Membros do grupo ativo. O admin convida amigos já aceitos.
class GroupMembersScreen extends StatefulWidget {
  const GroupMembersScreen({super.key, required this.controller});

  final RadarController controller;

  @override
  State<GroupMembersScreen> createState() => _GroupMembersScreenState();
}

class _GroupMembersScreenState extends State<GroupMembersScreen> {
  List<PendingGroupInvite> _pending = const [];
  bool _loadingPending = false;
  bool _pendingLoaded = false;

  RadarController get _controller => widget.controller;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_pendingLoaded || !_controller.isAdmin) return;
    _pendingLoaded = true;
    unawaited(_loadPending());
  }

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
    } on Object catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(friendErrorMessage(e))));
    }
  }

  Future<void> _loadPending() async {
    final groupId = _controller.groupId;
    if (groupId == null || !_controller.isAdmin) return;
    setState(() => _loadingPending = true);
    try {
      final list = await AppScope.of(
        context,
      ).friendService.listGroupPendingInvites(groupId);
      if (mounted) setState(() => _pending = list);
    } on Object catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(friendErrorMessage(e))));
      }
    } finally {
      if (mounted) setState(() => _loadingPending = false);
    }
  }

  String _subtitle(MemberLocation m) {
    if (m.status == 'paused') return 'Pausado';
    if (!m.isSharing) return 'Desligado';
    if (!m.hasPosition) return 'Compartilhe para ver';
    final battery = m.battery == null ? '' : ' · ${m.battery}%';
    return '${seenAgo(m.lastSeenAt)}$battery';
  }

  Future<void> _addFriends() async {
    final groupId = _controller.groupId;
    if (groupId == null) return;
    final friends = AppScope.of(context).friendService;
    final list = await friends.listFriends();
    final inGroup = _controller.members.map((m) => m.userId).toSet();
    final pendingIds = _pending.map((p) => p.inviteeId).toSet();
    final candidates = list.friends
        .where(
          (f) => !inGroup.contains(f.userId) && !pendingIds.contains(f.userId),
        )
        .toList();
    if (!mounted) return;
    if (candidates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Nenhum amigo disponível. Adicione amigos primeiro ou todos '
            'já estão no grupo.',
          ),
        ),
      );
      return;
    }

    final selected = await showModalBottomSheet<Set<String>>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _PickFriendsSheet(candidates: candidates),
    );
    if (selected == null || selected.isEmpty) return;
    await _run(() async {
      final count = await friends.inviteToGroup(groupId, selected.toList());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            count == 0
                ? 'Nenhum convite novo.'
                : '$count convite(s) enviado(s).',
          ),
        ),
      );
      await _loadPending();
    });
  }

  Future<void> _cancelInvite(PendingGroupInvite invite) async {
    final groupId = _controller.groupId;
    if (groupId == null) return;
    await _run(() async {
      await AppScope.of(
        context,
      ).friendService.cancelGroupInvite(groupId, invite.inviteeId);
      await _loadPending();
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        final members = _controller.friends;
        final groupId = _controller.groupId;
        final isAdmin = _controller.isAdmin;
        return Scaffold(
          appBar: AppBar(title: Text(_controller.activeGroupTitle)),
          floatingActionButton: Env.isDev && groupId != null
              ? FloatingActionButton.extended(
                  onPressed: () => _run(_controller.addFakeFriend),
                  icon: const Icon(Icons.person_add_alt_1),
                  label: const Text('Adicionar amigo simulado'),
                )
              : null,
          body: groupId == null
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Text(
                      'Crie um grupo para ver e convidar membros.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : Column(
                  children: [
                    if (isAdmin)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                        child: SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: _addFriends,
                            icon: const Icon(Icons.person_add),
                            label: const Text('Adicionar amigos'),
                          ),
                        ),
                      ),
                    if (isAdmin &&
                        (_pending.isNotEmpty || _loadingPending)) ...[
                      const Padding(
                        padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text('Convites pendentes'),
                        ),
                      ),
                      for (final p in _pending)
                        ListTile(
                          dense: true,
                          leading: CircleAvatar(
                            radius: 16,
                            child: Text(
                              p.displayName.isEmpty
                                  ? '?'
                                  : p.displayName[0].toUpperCase(),
                            ),
                          ),
                          title: Text(p.displayName),
                          subtitle: const Text('Aguardando aceite'),
                          trailing: TextButton(
                            onPressed: () => _cancelInvite(p),
                            child: const Text('Cancelar'),
                          ),
                        ),
                    ],
                    Expanded(
                      child: members.isEmpty
                          ? const Center(
                              child: Padding(
                                padding: EdgeInsets.all(32),
                                child: Text(
                                  'Ninguém no grupo ainda.\n'
                                  'Como admin, toque em Adicionar amigos.',
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            )
                          : ListView.separated(
                              padding: const EdgeInsets.only(
                                top: 8,
                                bottom: 96,
                              ),
                              itemCount: members.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox.shrink(),
                              itemBuilder: (context, i) {
                                final m = members[i];
                                return ListTile(
                                  dense: true,
                                  visualDensity: VisualDensity.compact,
                                  leading: CircleAvatar(
                                    radius: 16,
                                    backgroundColor: _controller.colorOf(
                                      m.userId,
                                    ),
                                    foregroundColor: Colors.white,
                                    child: Text(m.initial),
                                  ),
                                  title: Text(m.name),
                                  subtitle: Text(_subtitle(m)),
                                  onTap: m.hasPosition
                                      ? () => Navigator.pop(context, m.userId)
                                      : null,
                                  trailing: Env.isDev
                                      ? IconButton(
                                          tooltip: m.isSharing
                                              ? 'Simular: parar de compartilhar'
                                              : 'Simular: voltar a compartilhar',
                                          icon: Icon(
                                            m.isSharing
                                                ? Icons.location_on
                                                : Icons.location_off_outlined,
                                          ),
                                          onPressed: () => _run(
                                            () => _controller.toggleFakeFriend(
                                              m.userId,
                                            ),
                                          ),
                                        )
                                      : null,
                                );
                              },
                            ),
                    ),
                  ],
                ),
        );
      },
    );
  }
}

class _PickFriendsSheet extends StatefulWidget {
  const _PickFriendsSheet({required this.candidates});

  final List<Friend> candidates;

  @override
  State<_PickFriendsSheet> createState() => _PickFriendsSheetState();
}

class _PickFriendsSheetState extends State<_PickFriendsSheet> {
  final _selected = <String>{};

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.only(bottom: AppDimens.spaceMd),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(title: Text('Convidar amigos')),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final f in widget.candidates)
                    CheckboxListTile(
                      value: _selected.contains(f.userId),
                      onChanged: (v) {
                        setState(() {
                          if (v == true) {
                            _selected.add(f.userId);
                          } else {
                            _selected.remove(f.userId);
                          }
                        });
                      },
                      title: Text(f.displayName),
                      secondary: CircleAvatar(child: Text(f.initial)),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _selected.isEmpty
                      ? null
                      : () =>
                            Navigator.pop(context, Set<String>.from(_selected)),
                  child: Text('Enviar ${_selected.length} convite(s)'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
