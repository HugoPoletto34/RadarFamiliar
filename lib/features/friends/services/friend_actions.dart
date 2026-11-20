import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/auth/auth_redirect.dart';
import '../../../core/di/app_scope.dart';
import 'friend_service.dart';

/// Texto do pedido de amizade. O link fica sozinho na linha: o WhatsApp não
/// pode colar o scheme num domínio e descartar o código.
String friendShareMessage({required String code, required String link}) {
  return 'Adicione-me no Radar Familiar!\n\n'
      'Meu código: $code\n\n'
      '$link\n\n'
      'Baixe o app, crie sua conta e use "Adicionar amigo".';
}

Future<void> shareFriendCode(BuildContext context, {String? code}) async {
  final friends = AppScope.of(context).friendService;
  try {
    final value = code ?? await friends.myFriendCode();
    if (!context.mounted) return;
    final link = AuthRedirect.inviteLink(value);
    final message = friendShareMessage(code: value, link: link);
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
    ).showSnackBar(SnackBar(content: Text(friendErrorMessage(e))));
  }
}
