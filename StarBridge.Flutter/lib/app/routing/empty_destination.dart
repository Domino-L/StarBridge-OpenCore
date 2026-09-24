import 'package:flutter/widgets.dart';

class EmptyDestination extends StatelessWidget {
  const EmptyDestination({required this.semanticLabel, super.key});

  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: semanticLabel,
      child: const SizedBox.expand(),
    );
  }
}
