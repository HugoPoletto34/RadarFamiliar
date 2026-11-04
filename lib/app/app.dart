import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/config/env.dart';
import '../features/auth/sign_in_page.dart';
import '../features/home/home_page.dart';

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

class _AuthGate extends StatelessWidget {
  const _AuthGate();

  @override
  Widget build(BuildContext context) {
    final auth = Supabase.instance.client.auth;
    return StreamBuilder<AuthState>(
      stream: auth.onAuthStateChange,
      builder: (context, _) =>
          auth.currentSession == null ? const SignInPage() : const HomePage(),
    );
  }
}
