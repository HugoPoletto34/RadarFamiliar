import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/di/app_scope.dart';
import '../../../core/theme/app_dimens.dart';
import '../../../shared/widgets/error_box.dart';
import '../models/friend.dart';
import '../services/friend_service.dart';

/// Enviar pedido de amizade com o código (ou deep link).
class AddFriendScreen extends StatefulWidget {
  const AddFriendScreen({super.key, this.initialCode});

  final String? initialCode;

  @override
  State<AddFriendScreen> createState() => _AddFriendScreenState();
}

class _AddFriendScreenState extends State<AddFriendScreen> {
  final _code = TextEditingController();
  FriendService? _friends;
  bool _loadedInitial = false;

  FriendPreview? _preview;
  bool _busy = false;
  String? _error;
  DateTime? _birthDate;

  FriendService get _service => _friends!;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _friends ??= AppScope.of(context).friendService;
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
      _error = friendErrorMessage(e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _loadPreview() => _run(() async {
    final preview = await _service.previewFriendCode(_code.text.trim());
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

  Future<void> _send() => _run(() async {
    if (_birthDate == null) {
      setState(() => _error = 'Informe sua data de nascimento para continuar.');
      return;
    }
    await _service.ensureBirthDate(_birthDate!);
    final result = await _service.requestFriend(_code.text.trim());
    if (!mounted) return;
    final msg = result == 'accepted'
        ? 'Vocês já eram pedidos um do outro — amizade criada!'
        : 'Pedido enviado. Aguarde a aprovação.';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    Navigator.of(context).pop(true);
  });

  @override
  Widget build(BuildContext context) {
    final preview = _preview;
    return Scaffold(
      appBar: AppBar(title: const Text('Adicionar amigo')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppDimens.spaceLg),
          children: [
            TextField(
              controller: _code,
              enabled: !_busy,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: 'Código do amigo',
                hintText: 'Ex.: ABCD2345',
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _busy ? null : _loadPreview,
              child: const Text('Ver perfil'),
            ),
            if (preview != null) ...[
              const SizedBox(height: 24),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  child: Text(
                    preview.displayName.isEmpty
                        ? '?'
                        : preview.displayName[0].toUpperCase(),
                  ),
                ),
                title: Text(
                  preview.displayName,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                subtitle: const Text('Enviar pedido de amizade'),
              ),
              const SizedBox(height: 16),
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
                onPressed: _busy ? null : _send,
                child: const Text('Enviar pedido'),
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
