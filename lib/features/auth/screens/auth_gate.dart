import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/invites/invite_link.dart';
import '../../../core/invites/pending_invite.dart';
import '../../radar/screens/map_screen.dart';
import 'login_screen.dart';

/// Decide a tela inicial conforme a sessão do Supabase.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  final _appLinks = AppLinks();
  StreamSubscription<Uri>? _linkSub;
  String? _inviteAfterLogin;

  @override
  void initState() {
    super.initState();
    unawaited(_listenInviteLinks());
  }

  Future<void> _listenInviteLinks() async {
    final initial = await _appLinks.getInitialLink();
    if (initial != null) _onInviteUri(initial);
    _linkSub = _appLinks.uriLinkStream.listen(_onInviteUri);
  }

  void _onInviteUri(Uri uri) {
    final code = inviteCodeFromUri(uri);
    if (code == null) return;
    PendingInvite.set(code);
    if (Supabase.instance.client.auth.currentSession != null) {
      setState(() => _inviteAfterLogin = code);
    }
  }

  @override
  void dispose() {
    unawaited(_linkSub?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = Supabase.instance.client.auth;
    return StreamBuilder<AuthState>(
      stream: auth.onAuthStateChange,
      builder: (context, _) {
        if (auth.currentSession == null) {
          return const LoginScreen();
        }
        final inviteCode = _inviteAfterLogin ?? PendingInvite.take();
        return MapScreen(
          key: ValueKey(inviteCode ?? 'map'),
          pendingInviteCode: inviteCode,
          onConsumedPendingInvite: () {
            if (_inviteAfterLogin != null) {
              setState(() => _inviteAfterLogin = null);
            }
          },
        );
      },
    );
  }
}
