import 'package:flutter/material.dart';

import '../../design_system/tokens/starbridge_tokens.dart';

/// Functional feedback only. Reduced motion keeps a static progress track and
/// the accompanying status text; cached content remains fully interactive.
class MenuLoading extends StatelessWidget {
  const MenuLoading({super.key});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: RepaintBoundary(
      child: LinearProgressIndicator(
        minHeight: 2,
        value:
            MediaQuery.disableAnimationsOf(context) ||
                Theme.of(context)
                        .extension<StarBridgeTokens>()
                        ?.motion
                        .surfaceEnter ==
                    Duration.zero
            ? .5
            : null,
        semanticsLabel: '正在读取',
      ),
    ),
  );
}

/// Reserve a separate gutter so the thumb never covers message portraits.
class MenuChatScroll extends StatelessWidget {
  const MenuChatScroll({
    super.key,
    required this.controller,
    required this.child,
  });
  final ScrollController controller;
  final Widget child;
  @override
  Widget build(BuildContext context) => ScrollConfiguration(
    behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
    child: Scrollbar(
      key: const ValueKey('menu-chat-scrollbar'),
      controller: controller,
      thumbVisibility: true,
      trackVisibility: true,
      interactive: true,
      thickness: 8,
      radius: const Radius.circular(4),
      child: Padding(padding: const EdgeInsets.only(right: 16), child: child),
    ),
  );
}
