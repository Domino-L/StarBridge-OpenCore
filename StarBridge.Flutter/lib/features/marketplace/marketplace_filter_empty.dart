import 'package:flutter/material.dart';
import 'marketplace_copy.dart';
import 'marketplace_widgets.dart';

class MarketFilterEmpty extends StatelessWidget {
  const MarketFilterEmpty({required this.action, required this.clear, super.key});
  final String action;
  final VoidCallback clear;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(24),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Text(marketText(context, 'filteredEmpty')),
      const SizedBox(height: 12),
      marketTextAction(onPressed: clear,
        child: Text(marketText(context, action))),
    ]),
  );
}
