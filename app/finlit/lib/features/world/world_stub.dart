import 'package:flutter/material.dart';

/// Заглушка экрана нового мира, пока карточка потока B не сделана.
class WorldStubScreen extends StatelessWidget {
  const WorldStubScreen({super.key, required this.title, required this.card});

  final String title;

  /// Карточка из `docs/zadachi-agentam-29-09.md`, которая заменит заглушку.
  final String card;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(title)),
        body: Center(child: Text('$title — в работе ($card)')),
      );
}
