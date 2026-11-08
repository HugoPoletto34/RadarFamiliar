import 'package:flutter/material.dart';

import '../../../core/theme/app_dimens.dart';
import '../../../shared/widgets/error_box.dart';
import '../controllers/radar_controller.dart';
import '../models/radar_group.dart';

/// Formulário para criar um grupo nomeado (Família ou Amigos).
class CreateGroupScreen extends StatefulWidget {
  const CreateGroupScreen({super.key, required this.controller});

  final RadarController controller;

  @override
  State<CreateGroupScreen> createState() => _CreateGroupScreenState();
}

class _CreateGroupScreenState extends State<CreateGroupScreen> {
  final _name = TextEditingController();
  GroupKind _kind = GroupKind.family;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final validation = RadarGroup.validateName(_name.text);
    if (validation != null) {
      setState(() => _error = validation);
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.controller.createGroup(name: _name.text, kind: _kind);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on Object catch (e) {
      setState(() => _error = 'Não foi possível criar o grupo: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Criar grupo')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppDimens.spaceLg),
          children: [
            TextField(
              controller: _name,
              enabled: !_busy,
              textCapitalization: TextCapitalization.sentences,
              maxLength: RadarGroup.nameMaxLength,
              decoration: const InputDecoration(
                labelText: 'Nome do grupo',
                hintText: 'Ex.: Família Silva',
              ),
              onSubmitted: (_) => _busy ? null : _submit(),
            ),
            const SizedBox(height: AppDimens.spaceMd),
            Text(
              'Tipo do grupo',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: AppDimens.spaceSm),
            RadioGroup<GroupKind>(
              groupValue: _kind,
              onChanged: (value) {
                if (_busy || value == null) return;
                setState(() => _kind = value);
              },
              child: Column(
                children: [
                  for (final kind in GroupKind.values)
                    RadioListTile<GroupKind>(
                      contentPadding: EdgeInsets.zero,
                      value: kind,
                      enabled: !_busy,
                      title: Text(kind.label),
                      subtitle: Text(kind.description),
                    ),
                ],
              ),
            ),
            const SizedBox(height: AppDimens.spaceMd),
            FilledButton(
              onPressed: _busy ? null : _submit,
              child: _busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Criar grupo'),
            ),
            if (_error != null) ...[
              const SizedBox(height: AppDimens.spaceMd),
              ErrorBox(mensagem: _error!),
            ],
          ],
        ),
      ),
    );
  }
}
