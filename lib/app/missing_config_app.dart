import 'package:flutter/material.dart';

import '../core/config/env.dart';

/// Mostrada quando o app roda sem `--dart-define-from-file=env/<flavor>.json`.
class MissingConfigApp extends StatelessWidget {
  const MissingConfigApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      home: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Center(
              child: Text(
                'Configuração do Supabase ausente.\n\n'
                'Rode com --dart-define-from-file=env/${Env.flavor}.json '
                '(veja "Rodar no Android Studio" no README).',
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
