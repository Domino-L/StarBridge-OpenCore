import 'package:flutter/material.dart';

class MarketContextLayout extends StatelessWidget {
  const MarketContextLayout({required this.children, super.key});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) {
    if (MediaQuery.sizeOf(context).width <= 980) {
      return Wrap(
        spacing: 16,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: children,
      );
    }
    return Row(
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) const SizedBox(width: 16),
          if (i == 1) Expanded(child: children[i]) else children[i],
        ],
      ],
    );
  }
}
