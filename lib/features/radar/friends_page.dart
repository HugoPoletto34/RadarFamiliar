import 'package:flutter/material.dart';

import '../../core/config/env.dart';
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

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final friends = controller.friends;
        return Scaffold(
          appBar: AppBar(title: const Text('Amigos')),
          floatingActionButton: Env.isDev
              ? FloatingActionButton.extended(
                  onPressed: () => _run(context, controller.addFakeFriend),
                  icon: const Icon(Icons.person_add_alt_1),
                  label: const Text('Adicionar amigo simulado'),
                )
              : null,
          body: friends.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Text(
                      'Você ainda não tem amigos no grupo.\n'
                      'No modo dev, toque em "Adicionar amigo simulado".',
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.only(bottom: 96),
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
        );
      },
    );
  }
}
