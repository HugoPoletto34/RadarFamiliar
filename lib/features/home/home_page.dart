import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config/env.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = Supabase.instance.client.auth;
    final user = auth.currentUser;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Radar Familiar'),
        actions: [
          IconButton(
            tooltip: 'Sair',
            icon: const Icon(Icons.logout),
            onPressed: auth.signOut,
          ),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Olá, mundo!',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 8),
            Text('Conectado como ${user?.email ?? user?.id}'),
            const SizedBox(height: 8),
            const Text('Ambiente: ${Env.flavor}'),
          ],
        ),
      ),
    );
  }
}
