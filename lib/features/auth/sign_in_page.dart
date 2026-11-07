import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/auth/auth_redirect.dart';

/// Login com Google ou e-mail e senha. Código de 6 dígitos só na confirmação
/// do cadastro por e-mail (não no login diário).
class SignInPage extends StatefulWidget {
  const SignInPage({super.key});

  @override
  State<SignInPage> createState() => _SignInPageState();
}

class _SignInPageState extends State<SignInPage> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _code = TextEditingController();

  bool _registerMode = false;
  bool _awaitingEmailConfirm = false;
  bool _obscurePassword = true;
  bool _busy = false;
  String? _error;

  GoTrueClient get _auth => Supabase.instance.client.auth;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
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
      if (!_registerMode &&
          !_awaitingEmailConfirm &&
          e.message.toLowerCase().contains('email not confirmed')) {
        setState(() {
          _awaitingEmailConfirm = true;
          _error = null;
        });
        return;
      }
      _error = _friendlyAuthError(e);
    } on Object catch (e) {
      _error = 'Erro inesperado: $e';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _friendlyAuthError(AuthException e) {
    final msg = e.message.toLowerCase();
    if (msg.contains('email not confirmed')) {
      return 'Confirme seu e-mail com o código de 6 dígitos antes de entrar.';
    }
    if (msg.contains('invalid login credentials')) {
      return 'E-mail ou senha incorretos.';
    }
    return e.message;
  }

  String get _trimmedEmail => _email.text.trim();

  Future<void> _signInWithGoogle() => _run(() async {
    await _auth.signInWithOAuth(
      OAuthProvider.google,
      redirectTo: AuthRedirect.uri,
      authScreenLaunchMode: LaunchMode.externalApplication,
    );
  });

  Future<void> _signInWithPassword() => _run(() async {
    await _auth.signInWithPassword(
      email: _trimmedEmail,
      password: _password.text,
    );
  });

  Future<void> _signUp() => _run(() async {
    final response = await _auth.signUp(
      email: _trimmedEmail,
      password: _password.text,
    );
    if (response.session != null) return;
    setState(() {
      _awaitingEmailConfirm = true;
      _error = null;
    });
  });

  Future<void> _confirmSignUpCode() => _run(() async {
    await _auth.verifyOTP(
      type: OtpType.signup,
      email: _trimmedEmail,
      token: _code.text.trim(),
    );
  });

  Future<void> _resendSignUpCode() => _run(() async {
    await _auth.resend(type: OtpType.signup, email: _trimmedEmail);
  });

  void _toggleMode() {
    setState(() {
      _registerMode = !_registerMode;
      _awaitingEmailConfirm = false;
      _error = null;
      _code.clear();
    });
  }

  Future<void> _submitPrimary() async {
    if (_awaitingEmailConfirm) {
      await _confirmSignUpCode();
      return;
    }
    if (_registerMode) {
      await _signUp();
      return;
    }
    await _signInWithPassword();
  }

  @override
  Widget build(BuildContext context) {
    final title = _awaitingEmailConfirm
        ? 'Confirmar e-mail'
        : (_registerMode ? 'Criar conta' : 'Entrar');

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            if (!_awaitingEmailConfirm) ...[
              OutlinedButton.icon(
                onPressed: _busy ? null : _signInWithGoogle,
                icon: const Icon(Icons.g_mobiledata, size: 28),
                label: const Text('Continuar com Google'),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  const Expanded(child: Divider()),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text(
                      'ou e-mail e senha',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  const Expanded(child: Divider()),
                ],
              ),
              const SizedBox(height: 24),
            ],
            TextField(
              controller: _email,
              enabled: !_awaitingEmailConfirm && !_busy,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              decoration: const InputDecoration(labelText: 'E-mail'),
            ),
            if (!_awaitingEmailConfirm) ...[
              const SizedBox(height: 16),
              TextField(
                controller: _password,
                enabled: !_busy,
                obscureText: _obscurePassword,
                autofillHints: _registerMode
                    ? const [AutofillHints.newPassword]
                    : const [AutofillHints.password],
                decoration: InputDecoration(
                  labelText: 'Senha',
                  suffixIcon: IconButton(
                    onPressed: () =>
                        setState(() => _obscurePassword = !_obscurePassword),
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                  ),
                ),
              ),
            ],
            if (_awaitingEmailConfirm) ...[
              const SizedBox(height: 16),
              Text(
                'Enviamos um código de 6 dígitos para $_trimmedEmail. '
                'Digite-o abaixo para confirmar o cadastro.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _code,
                keyboardType: TextInputType.number,
                autofillHints: const [AutofillHints.oneTimeCode],
                decoration: const InputDecoration(
                  labelText: 'Código de confirmação',
                ),
              ),
            ],
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _busy ? null : _submitPrimary,
              child: Text(
                _awaitingEmailConfirm
                    ? 'Confirmar cadastro'
                    : (_registerMode ? 'Cadastrar' : 'Entrar'),
              ),
            ),
            if (_awaitingEmailConfirm)
              TextButton(
                onPressed: _busy ? null : _resendSignUpCode,
                child: const Text('Reenviar código'),
              ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _busy
                  ? null
                  : () {
                      if (_awaitingEmailConfirm) {
                        setState(() {
                          _awaitingEmailConfirm = false;
                          _code.clear();
                        });
                      } else {
                        _toggleMode();
                      }
                    },
              child: Text(
                _awaitingEmailConfirm
                    ? 'Voltar'
                    : (_registerMode
                          ? 'Já tenho conta — entrar'
                          : 'Não tenho conta — cadastrar'),
              ),
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
