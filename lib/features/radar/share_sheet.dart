import 'package:flutter/material.dart';

import 'member_location.dart';

/// Resultado da folha: minutos (15 ou 60), [untilOff] ou [stop].
class ShareChoice {
  const ShareChoice._(this.minutes, {this.stop = false});

  static const min15 = ShareChoice._(15);
  static const min60 = ShareChoice._(60);
  static const untilOff = ShareChoice._(null);
  static const stopSharing = ShareChoice._(null, stop: true);

  final int? minutes;
  final bool stop;
}

Future<ShareChoice?> showShareSheet(BuildContext context, SharingState state) {
  return showModalBottomSheet<ShareChoice>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Text(
              'Compartilhar minha localização com Amigos',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          ListTile(
            leading: const Icon(Icons.timer_outlined),
            title: const Text('Por 15 minutos'),
            onTap: () => Navigator.pop(context, ShareChoice.min15),
          ),
          ListTile(
            leading: const Icon(Icons.hourglass_bottom),
            title: const Text('Por 1 hora'),
            onTap: () => Navigator.pop(context, ShareChoice.min60),
          ),
          ListTile(
            leading: const Icon(Icons.all_inclusive),
            title: const Text('Até eu desligar'),
            onTap: () => Navigator.pop(context, ShareChoice.untilOff),
          ),
          if (state.on)
            ListTile(
              leading: const Icon(Icons.location_off_outlined),
              title: const Text('Parar de compartilhar'),
              textColor: Theme.of(context).colorScheme.error,
              iconColor: Theme.of(context).colorScheme.error,
              onTap: () => Navigator.pop(context, ShareChoice.stopSharing),
            ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}

String hhmm(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

String sharingLabel(SharingState s) {
  if (!s.on || s.expired) return 'Você não está compartilhando';
  if (s.until == null) return 'Compartilhando até você desligar';
  return 'Compartilhando até ${hhmm(s.until!)}';
}

String shortSharingLabel(SharingState s) {
  if (!s.on || s.expired) return 'Não compartilhando';
  if (s.until == null) return 'Compartilhando';
  return 'Compartilhando até ${hhmm(s.until!)}';
}

String seenAgo(DateTime? t) {
  if (t == null) return '';
  final d = DateTime.now().difference(t.toLocal());
  if (d.inSeconds < 60) return 'agora';
  if (d.inMinutes < 60) return 'há ${d.inMinutes} min';
  return 'há ${d.inHours} h';
}
