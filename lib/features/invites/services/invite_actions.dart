import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/auth/auth_redirect.dart';
import '../../../core/di/app_scope.dart';
import 'invite_service.dart';

/// Texto do convite. O link fica sozinho na linha: o WhatsApp não pode
/// colar o scheme num domínio e descartar o código.
String inviteShareMessage({required String code, required String link}) {
  return 'Entre no meu Radar Familiar!\n\n'
      'Código: $code\n\n'
      '$link\n\n'
      'Baixe o app, crie sua conta e use "Entrar com convite".';
}

Future<void> shareGroupInvite(BuildContext context, String groupId) async {
  final invites = AppScope.of(context).inviteService;
  try {
    final invite = await invites.createInvite(groupId);
    if (!context.mounted) return;
    final link = AuthRedirect.inviteLink(invite.code);
    final message = inviteShareMessage(code: invite.code, link: link);
    final box = context.findRenderObject();
    final origin = box is RenderBox && box.hasSize && !box.size.isEmpty
        ? box.localToGlobal(Offset.zero) & box.size
        : null;
    await SharePlus.instance.share(
      ShareParams(text: message, sharePositionOrigin: origin),
    );
  } on Object catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(inviteErrorMessage(e))));
  }
}
