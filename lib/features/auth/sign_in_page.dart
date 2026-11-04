import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Login por código de 6 dígitos enviado por e-mail (OTP). Google e Apple
/// entram no M2, junto com data de nascimento e aceite dos termos.
class SignInPage extends StatefulWidget {
  const SignInPage({super.key});

  @override
  State<SignInPage> createState() => _SignInPageState();
}

class _SignInPageState extends State<SignInPage> {
  final _email = TextEditingController();
  final _code = TextEditingController();
  bool _codeSent = false;
  bool _busy = false;
  String? _error;

  GoTrueClient get _auth => Supabase.instance.client.auth;

  @override
  void dispose() {
    _email.dispose();
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
    } on AuthException catch (e) {
      _error = e.message;
    } on Object catch (e) {
      _error = 'Erro inesperado: $e';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sendCode() => _run(() async {
    await _auth.signInWithOtp(email: _email.text.trim());
    _codeSent = true;
  });

  Future<void> _verify() => _run(() async {
    await _auth.verifyOTP(
      type: OtpType.email,
      email: _email.text.trim(),
      token: _code.text.trim(),
    );
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Entrar')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            TextField(
              controller: _email,
              enabled: !_codeSent,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              decoration: const InputDecoration(labelText: 'E-mail'),
            ),
            if (_codeSent) ...[
              const SizedBox(height: 16),
              TextField(
                controller: _code,
                keyboardType: TextInputType.number,
                autofillHints: const [AutofillHints.oneTimeCode],
                decoration: const InputDecoration(
                  labelText: 'Código recebido por e-mail',
                ),
              ),
            ],
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _busy ? null : (_codeSent ? _verify : _sendCode),
              child: Text(_codeSent ? 'Confirmar código' : 'Enviar código'),
            ),
            if (_codeSent)
              TextButton(
                onPressed: _busy
                    ? null
                    : () => setState(() => _codeSent = false),
                child: const Text('Trocar e-mail'),
              ),
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
}
