import 'package:flutter/material.dart';

import '../../../core/di/app_scope.dart';
import '../../../core/theme/app_dimens.dart';
import '../../../shared/widgets/error_box.dart';
import '../../../shared/widgets/loading_view.dart';
import '../../friends/models/friend.dart';
import '../../friends/services/friend_service.dart';
import '../controllers/radar_controller.dart';
import '../models/radar_group.dart';
import 'create_group_screen.dart';

/// Lista os grupos do usuário e permite trocar o ativo ou criar um novo.
class GroupsScreen extends StatefulWidget {
  const GroupsScreen({super.key, required this.controller});

  final RadarController controller;

  @override
  State<GroupsScreen> createState() => _GroupsScreenState();
}

class _GroupsScreenState extends State<GroupsScreen> {
  late Future<List<RadarGroup>> _groupsFuture;
  List<GroupInvite> _invites = const [];
  bool _loadingInvites = true;

  bool _invitesStarted = false;

  @override
  void initState() {
    super.initState();
    _groupsFuture = widget.controller.listGroups();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_invitesStarted) return;
    _invitesStarted = true;
    _loadInvites();
  }

  void _reload() {
    setState(() {
      _groupsFuture = widget.controller.listGroups();
    });
    _loadInvites();
  }

  Future<void> _loadInvites() async {
    setState(() => _loadingInvites = true);
    try {
      final list = await AppScope.of(context).friendService.myGroupInvites();
      if (mounted) setState(() => _invites = list);
    } on Object catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(friendErrorMessage(e))));
      }
    } finally {
      if (mounted) setState(() => _loadingInvites = false);
    }
  }

  Future<void> _respondInvite(
    GroupInvite invite, {
    required bool accept,
  }) async {
    try {
      final groupId = await AppScope.of(
        context,
      ).friendService.respondGroupInvite(invite.groupId, accept: accept);
      if (!mounted) return;
      if (accept && groupId != null) {
        await widget.controller.useGroup(groupId);
        if (!mounted) return;
        Navigator.of(context).pop(true);
        return;
      }
      await _loadInvites();
    } on Object catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(friendErrorMessage(e))));
    }
  }

  Future<void> _openCreate() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => CreateGroupScreen(controller: widget.controller),
      ),
    );
    if (created == true && mounted) {
      Navigator.of(context).pop(true);
    }
  }

  Future<void> _select(RadarGroup group) async {
    if (group.id == widget.controller.groupId) {
      Navigator.of(context).pop(false);
      return;
    }
    try {
      await widget.controller.useGroup(group.id);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on Object catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Não foi possível trocar: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Grupos')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openCreate,
        icon: const Icon(Icons.group_add),
        label: const Text('Criar grupo'),
      ),
      body: FutureBuilder<List<RadarGroup>>(
        future: _groupsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done &&
              _loadingInvites) {
            return const LoadingView(mensagem: 'Carregando grupos…');
          }
          if (snapshot.hasError) {
            return Padding(
              padding: const EdgeInsets.all(AppDimens.spaceLg),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ErrorBox(mensagem: 'Falha ao listar: ${snapshot.error}'),
                  const SizedBox(height: AppDimens.spaceMd),
                  FilledButton(
                    onPressed: _reload,
                    child: const Text('Tentar de novo'),
                  ),
                ],
              ),
            );
          }

          final groups = snapshot.data ?? const [];
          return ListView(
            padding: const EdgeInsets.fromLTRB(0, AppDimens.spaceSm, 0, 96),
            children: [
              if (_invites.isNotEmpty) ...[
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: Text('Convites recebidos'),
                ),
                for (final invite in _invites)
                  ListTile(
                    leading: const Icon(Icons.mail_outline),
                    title: Text(invite.groupName),
                    subtitle: Text('Convite de ${invite.invitedByName}'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextButton(
                          onPressed: () =>
                              _respondInvite(invite, accept: false),
                          child: const Text('Recusar'),
                        ),
                        FilledButton(
                          onPressed: () => _respondInvite(invite, accept: true),
                          child: const Text('Aceitar'),
                        ),
                      ],
                    ),
                  ),
                const Divider(),
              ],
              if (groups.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(AppDimens.spaceXl),
                  child: Text(
                    'Nenhum grupo ainda.\nToque em Criar grupo para começar.',
                    textAlign: TextAlign.center,
                  ),
                )
              else ...[
                for (var i = 0; i < groups.length; i++) ...[
                  if (i > 0) const Divider(height: 1),
                  Builder(
                    builder: (context) {
                      final group = groups[i];
                      final selected = group.id == widget.controller.groupId;
                      return ListTile(
                        leading: Icon(
                          group.kind == GroupKind.family
                              ? Icons.family_restroom
                              : Icons.groups_outlined,
                        ),
                        title: Text(group.name),
                        subtitle: Text(group.kind.label),
                        trailing: selected
                            ? Icon(
                                Icons.check_circle,
                                color: Theme.of(context).colorScheme.primary,
                              )
                            : null,
                        selected: selected,
                        onTap: () => _select(group),
                      );
                    },
                  ),
                ],
              ],
            ],
          );
        },
      ),
    );
  }
}
