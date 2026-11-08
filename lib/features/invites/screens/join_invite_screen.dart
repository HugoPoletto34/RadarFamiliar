import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/di/app_scope.dart';
import '../../../core/theme/app_dimens.dart';
import '../../../shared/widgets/error_box.dart';
import '../models/invite_preview.dart';
import '../services/invite_service.dart';

/// Entrar em um grupo com o código (ou deep link). Exige data de nascimento se
/// o perfil ainda não tiver (regra do servidor para aceitar convite).
class JoinInviteScreen extends StatefulWidget {
  const JoinInviteScreen({super.key, this.initialCode});

  final String? initialCode;

  @override
  State<JoinInviteScreen> createState() => _JoinInviteScreenState();
}

class _JoinInviteScreenState extends State<JoinInviteScreen> {
  final _code = TextEditingController();
  InviteService? _invites;
  bool _loadedInitial = false;

  InvitePreview? _preview;
  bool _busy = false;
  String? _error;
  DateTime? _birthDate;

  InviteService get _service => _invites!;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _invites ??= AppScope.of(context).inviteService;
    if (!_loadedInitial && widget.initialCode != null) {
      _loadedInitial = true;
      _code.text = widget.initialCode!;
      unawaited(_loadPreview());
    }
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } on Object catch (e) {
      _error = inviteErrorMessage(e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _loadPreview() => _run(() async {
    final preview = await _service.previewInvite(_code.text.trim());
    final birth = await _service.birthDate();
    setState(() {
      _preview = preview;
      _birthDate = birth;
    });
  });

  Future<void> _pickBirthDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(now.year - 25, now.month, now.day),
      firstDate: DateTime(1900),
      lastDate: DateTime(now.year - 18, now.month, now.day),
      helpText: 'Data de nascimento',
    );
    if (picked != null) setState(() => _birthDate = picked);
  }

  Future<void> _accept() => _run(() async {
    if (_birthDate == null) {
      setState(() => _error = 'Informe sua data de nascimento para continuar.');
      return;
    }
    await _service.ensureBirthDate(_birthDate!);
    final groupId = await _service.acceptInvite(_code.text.trim());
    if (!mounted) return;
    Navigator.of(context).pop(groupId);
  });

  @override
  Widget build(BuildContext context) {
    final preview = _preview;
    return Scaffold(
      appBar: AppBar(title: const Text('Entrar com convite')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppDimens.spaceLg),
          children: [
            TextField(
              controller: _code,
              enabled: !_busy,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: 'Código do convite',
                hintText: 'Ex.: ABCD2345',
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _busy ? null : _loadPreview,
              child: const Text('Ver convite'),
            ),
            if (preview != null) ...[
              const SizedBox(height: 24),
              Text(
                preview.groupName,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text('Convite de ${preview.invitedBy}'),
              if (preview.memberNames.isNotEmpty)
                Text(
                  'No grupo: ${preview.memberNames.join(', ')}',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              Text(
                'Válido até ${_formatDate(preview.expiresAt)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 24),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Data de nascimento'),
                subtitle: Text(
                  _birthDate == null
                      ? 'Obrigatório — maior de 18 anos'
                      : _formatDate(_birthDate!),
                ),
                trailing: const Icon(Icons.calendar_month),
                onTap: _busy ? null : _pickBirthDate,
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _busy ? null : _accept,
                child: const Text('Aceitar e entrar no grupo'),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: AppDimens.spaceMd),
              ErrorBox(mensagem: _error!),
            ],
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/'
      '${d.month.toString().padLeft(2, '0')}/'
      '${d.year}';
}
