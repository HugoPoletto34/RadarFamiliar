import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'invite_preview.dart';
import 'invite_repository.dart';

/// Entrar em um grupo com o código (ou deep link). Exige data de nascimento se
/// o perfil ainda não tiver (regra do servidor para aceitar convite).
class JoinInvitePage extends StatefulWidget {
  const JoinInvitePage({super.key, this.initialCode});

  final String? initialCode;

  @override
  State<JoinInvitePage> createState() => _JoinInvitePageState();
}

class _JoinInvitePageState extends State<JoinInvitePage> {
  final _code = TextEditingController();
  late final InviteRepository _repo = InviteRepository(
    Supabase.instance.client,
  );

  InvitePreview? _preview;
  bool _busy = false;
  String? _error;
  DateTime? _birthDate;

  @override
  void initState() {
    super.initState();
    if (widget.initialCode != null) {
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
    final preview = await _repo.previewInvite(_code.text.trim());
    final birth = await _repo.birthDate();
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
    await _repo.ensureBirthDate(_birthDate!);
    final groupId = await _repo.acceptInvite(_code.text.trim());
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
          padding: const EdgeInsets.all(24),
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
              const SizedBox(height: 16),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
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
