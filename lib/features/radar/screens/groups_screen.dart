import 'package:flutter/material.dart';

import '../../../core/theme/app_dimens.dart';
import '../../../shared/widgets/error_box.dart';
import '../../../shared/widgets/loading_view.dart';
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

  @override
  void initState() {
    super.initState();
    _groupsFuture = widget.controller.listGroups();
  }

  void _reload() {
    setState(() {
      _groupsFuture = widget.controller.listGroups();
    });
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
          if (snapshot.connectionState != ConnectionState.done) {
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
          if (groups.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(AppDimens.spaceXl),
                child: Text(
                  'Nenhum grupo ainda.\nToque em Criar grupo para começar.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          final activeId = widget.controller.groupId;
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(0, AppDimens.spaceSm, 0, 96),
            itemCount: groups.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final group = groups[i];
              final selected = group.id == activeId;
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
          );
        },
      ),
    );
  }
}
