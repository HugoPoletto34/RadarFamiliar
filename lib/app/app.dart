import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/config/env.dart';
import '../core/invites/invite_link.dart';
import '../core/invites/pending_invite.dart';
import '../features/auth/sign_in_page.dart';
import '../features/radar/map_page.dart';

class RadarFamiliarApp extends StatelessWidget {
  const RadarFamiliarApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Radar Familiar',
      debugShowCheckedModeBanner: !Env.isProd,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1E6B52)),
      ),
      home: const _AuthGate(),
    );
  }
}

class _AuthGate extends StatefulWidget {
  const _AuthGate();

  @override
  State<_AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<_AuthGate> {
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
          return const SignInPage();
        }
        final inviteCode = _inviteAfterLogin ?? PendingInvite.take();
        return MapPage(
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
