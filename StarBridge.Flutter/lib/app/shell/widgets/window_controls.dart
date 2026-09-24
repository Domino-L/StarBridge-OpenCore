import 'dart:async';

import 'package:flutter/material.dart';

import '../../../design_system/icons/icon_semantic.dart';
import '../../../design_system/icons/starbridge_icon.dart';
import '../../../design_system/tokens/starbridge_tokens.dart';
import '../../../platform/window/window_chrome_port.dart';
import '../../localization/app_strings.dart';

class WindowControls extends StatelessWidget {
  const WindowControls({required this.windowChrome, super.key});

  final WindowChromePort windowChrome;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _WindowControl(
          semantic: StarBridgeIconSemantic.windowMinimize,
          tooltip: strings.text('window.minimize'),
          onPressed: () => unawaited(windowChrome.minimize()),
        ),
        ValueListenableBuilder<bool>(
          valueListenable: windowChrome.isMaximized,
          builder: (context, isMaximized, _) => _WindowControl(
            key: const Key('window-maximize-control'),
            semantic: isMaximized
                ? StarBridgeIconSemantic.windowRestore
                : StarBridgeIconSemantic.windowMaximize,
            tooltip: strings.text(
              isMaximized ? 'window.restore' : 'window.maximize',
            ),
            onPressed: () => unawaited(windowChrome.toggleMaximize()),
          ),
        ),
        _WindowControl(
          semantic: StarBridgeIconSemantic.windowClose,
          tooltip: strings.text('window.close'),
          danger: true,
          onPressed: () => unawaited(windowChrome.close()),
        ),
      ],
    );
  }
}

class _WindowControl extends StatelessWidget {
  const _WindowControl({
    required this.semantic,
    required this.tooltip,
    required this.onPressed,
    this.danger = false,
    super.key,
  });

  final StarBridgeIconSemantic semantic;
  final String tooltip;
  final VoidCallback onPressed;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return IconButton(
      onPressed: onPressed,
      tooltip: tooltip,
      style: ButtonStyle(
        minimumSize: WidgetStatePropertyAll(
          Size(
            tokens.density.controlHeight + tokens.space.sm,
            tokens.density.topBarHeight,
          ),
        ),
        side: const WidgetStatePropertyAll(BorderSide.none),
        shape: const WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        ),
        foregroundColor: WidgetStateProperty.resolveWith((states) {
          if (danger && states.contains(WidgetState.hovered)) {
            return tokens.colors.onAccent;
          }
          return tokens.colors.textSecondary;
        }),
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          if (danger && states.contains(WidgetState.hovered)) {
            return tokens.colors.danger;
          }
          if (states.contains(WidgetState.hovered)) {
            return tokens.surfaces.raised.fill;
          }
          return tokens.surfaces.chrome.fill;
        }),
      ),
      icon: StarBridgeIcon(semantic, size: tokens.icons.small),
    );
  }
}
