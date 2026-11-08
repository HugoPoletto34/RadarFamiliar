import 'package:flutter/material.dart';

/// Indicador de progresso centralizado com uma mensagem.
class LoadingView extends StatelessWidget {
  const LoadingView({super.key, required this.mensagem});

  final String mensagem;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 24),
          Text(mensagem, style: Theme.of(context).textTheme.titleMedium),
        ],
      ),
    );
  }
}
