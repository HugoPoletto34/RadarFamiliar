import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/auth/auth_redirect.dart';
import 'invite_repository.dart';

Future<void> shareGroupInvite(BuildContext context, String groupId) async {
  final repo = InviteRepository(Supabase.instance.client);
  try {
    final invite = await repo.createInvite(groupId);
    final link = AuthRedirect.inviteLink(invite.code);
    final message =
        'Entre no meu Radar Familiar!\n\n'
        'Código: ${invite.code}\n'
        'Ou abra o link: $link\n\n'
        'Baixe o app, crie sua conta e use "Entrar com convite".';
    await Share.share(message, subject: 'Convite Radar Familiar');
  } on Object catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(inviteErrorMessage(e))),
    );
  }
}
