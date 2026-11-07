import 'package:flutter/material.dart';

import '../../core/config/env.dart';
import '../invites/invite_actions.dart';
import '../invites/join_invite_page.dart';
import 'member_location.dart';
import 'radar_controller.dart';
import 'share_sheet.dart';

/// Lista de amigos. Tocar em um amigo visível volta ao mapa centrado nele.
class FriendsPage extends StatelessWidget {
  const FriendsPage({super.key, required this.controller});

  final RadarController controller;

  Future<void> _run(
    BuildContext context,
    Future<void> Function() action,
  ) async {
    try {
      await action();
    } on Object catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  String _subtitle(MemberLocation m) {
    if (m.status == 'paused') return 'Pausado';
    if (!m.isSharing) return 'Desligado';
    if (!m.hasPosition) return 'Compartilhe para ver';
    final battery = m.battery == null ? '' : ' · ${m.battery}%';
    return '${seenAgo(m.lastSeenAt)}$battery';
  }

  Future<void> _joinInvite(BuildContext context) async {
    final groupId = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const JoinInvitePage()),
    );
    if (groupId != null) await controller.useGroup(groupId);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final friends = controller.friends;
        final groupId = controller.groupId;
        return Scaffold(
          appBar: AppBar(title: const Text('Amigos')),
          floatingActionButton: Env.isDev
              ? FloatingActionButton.extended(
                  onPressed: () => _run(context, controller.addFakeFriend),
                  icon: const Icon(Icons.person_add_alt_1),
                  label: const Text('Adicionar amigo simulado'),
                )
              : null,
          body: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: groupId == null
                            ? null
                            : () => shareGroupInvite(context, groupId),
                        icon: const Icon(Icons.share),
                        label: const Text('Convidar'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _joinInvite(context),
                        icon: const Icon(Icons.vpn_key_outlined),
                        label: const Text('Tenho código'),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: friends.isEmpty
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(32),
                          child: Text(
                            'Ninguém no grupo ainda.\n'
                            'Toque em Convidar e envie o link no WhatsApp, '
                            'ou use Tenho código se alguém te convidou.',
                            textAlign: TextAlign.center,
                          ),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.only(
                          top: 8,
                          bottom: 96,
                        ),
                        itemCount: friends.length,
                        separatorBuilder: (_, _) => const SizedBox.shrink(),
                        itemBuilder: (context, i) {
                          final m = friends[i];
                          return ListTile(
                            dense: true,
                            visualDensity: VisualDensity.compact,
                            leading: CircleAvatar(
                              radius: 16,
                              backgroundColor: controller.colorOf(m.userId),
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
                                      context,
                                      () => controller.toggleFakeFriend(m.userId),
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
