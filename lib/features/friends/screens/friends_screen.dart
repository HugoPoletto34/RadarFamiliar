import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/di/app_scope.dart';
import '../../../core/theme/app_dimens.dart';
import '../../../shared/widgets/error_box.dart';
import '../../../shared/widgets/loading_view.dart';
import '../controllers/friends_controller.dart';
import '../models/friend.dart';
import '../services/friend_actions.dart';
import '../services/friend_service.dart';
import 'add_friend_screen.dart';

/// Lista de amigos, pedidos e código pessoal permanente.
class FriendsScreen extends StatefulWidget {
  const FriendsScreen({super.key});

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen> {
  FriendsController? _controller;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller != null) return;
    _controller = FriendsController(AppScope.of(context).friendService)
      ..addListener(_onChange);
    _controller!.load();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller
      ?..removeListener(_onChange)
      ..dispose();
    super.dispose();
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

  Future<void> _copyCode(String code) async {
    await Clipboard.setData(ClipboardData(text: code));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Código copiado')));
  }

  Future<void> _regenerate() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Gerar novo código?'),
        content: const Text(
          'O código atual deixa de valer. Quem ainda não enviou o pedido '
          'precisará do código novo.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Gerar novo'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _run(_controller!.regenerateCode);
  }

  Future<void> _removeFriend(Friend friend) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Remover ${friend.displayName}?'),
        content: const Text(
          'Vocês deixam de ser amigos. Isso não remove ninguém de grupos '
          'em comum.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remover'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _run(() => _controller!.removeFriend(friend.userId));
  }

  Future<void> _addFriend() async {
    await Navigator.of(
      context,
    ).push<bool>(MaterialPageRoute(builder: (_) => const AddFriendScreen()));
    await _controller?.load();
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    if (c == null || (c.loading && c.code == null)) {
      return const Scaffold(body: LoadingView(mensagem: 'Carregando amigos…'));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Amigos')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addFriend,
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('Adicionar amigo'),
      ),
      body: RefreshIndicator(
        onRefresh: c.load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(0, 8, 0, 96),
          children: [
            if (c.error != null)
              Padding(
                padding: const EdgeInsets.all(AppDimens.spaceLg),
                child: ErrorBox(mensagem: c.error!),
              ),
            if (c.code != null)
              _CodeCard(
                code: c.code!,
                onCopy: () => _copyCode(c.code!),
                onShare: () => shareFriendCode(context, code: c.code),
                onRegenerate: _regenerate,
              ),
            if (c.incoming.isNotEmpty) ...[
              const _SectionTitle('Pedidos recebidos'),
              for (final r in c.incoming)
                ListTile(
                  leading: CircleAvatar(child: Text(r.initial)),
                  title: Text(r.displayName),
                  subtitle: const Text('Quer ser seu amigo'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Recusar',
                        icon: const Icon(Icons.close),
                        onPressed: () => _run(() => c.declineRequest(r.userId)),
                      ),
                      IconButton(
                        tooltip: 'Aceitar',
                        icon: const Icon(Icons.check),
                        onPressed: () => _run(() => c.acceptRequest(r.userId)),
                      ),
                    ],
                  ),
                ),
            ],
            if (c.outgoing.isNotEmpty) ...[
              const _SectionTitle('Pedidos enviados'),
              for (final r in c.outgoing)
                ListTile(
                  leading: CircleAvatar(child: Text(r.initial)),
                  title: Text(r.displayName),
                  subtitle: const Text('Aguardando resposta'),
                  trailing: TextButton(
                    onPressed: () => _run(() => c.cancelRequest(r.userId)),
                    child: const Text('Cancelar'),
                  ),
                ),
            ],
            const _SectionTitle('Seus amigos'),
            if (c.friends.isEmpty)
              const Padding(
                padding: EdgeInsets.all(AppDimens.spaceXl),
                child: Text(
                  'Nenhum amigo ainda.\n'
                  'Compartilhe seu código ou toque em Adicionar amigo.',
                  textAlign: TextAlign.center,
                ),
              )
            else
              for (final f in c.friends)
                ListTile(
                  leading: CircleAvatar(child: Text(f.initial)),
                  title: Text(f.displayName),
                  trailing: IconButton(
                    tooltip: 'Desfazer amizade',
                    icon: const Icon(Icons.person_remove_outlined),
                    onPressed: () => _removeFriend(f),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

class _CodeCard extends StatelessWidget {
  const _CodeCard({
    required this.code,
    required this.onCopy,
    required this.onShare,
    required this.onRegenerate,
  });

  final String code;
  final VoidCallback onCopy;
  final VoidCallback onShare;
  final VoidCallback onRegenerate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Padding(
        padding: const EdgeInsets.all(AppDimens.spaceMd),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Meu código', style: theme.textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(
              code,
              style: theme.textTheme.headlineSmall?.copyWith(
                letterSpacing: 2,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Não expira. Quem usar envia um pedido que você aprova.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonalIcon(
                  onPressed: onCopy,
                  icon: const Icon(Icons.copy),
                  label: const Text('Copiar'),
                ),
                FilledButton.icon(
                  onPressed: onShare,
                  icon: const Icon(Icons.share),
                  label: const Text('Compartilhar'),
                ),
                TextButton(
                  onPressed: onRegenerate,
                  child: const Text('Gerar novo'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(text, style: Theme.of(context).textTheme.titleSmall),
    );
  }
}
