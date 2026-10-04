import 'package:flutter/material.dart';

import '../../design_system/icons/window_control_icon.dart';
import '../../design_system/styles/window_caption_palette.dart';

import '../../design_system/tokens/starbridge_tokens.dart';

/// Geometry is paired with native caption hit-testing: 34 high, 3 x 44 controls.
class SocialWindowFrame extends StatelessWidget {
  const SocialWindowFrame({
    required this.title,
    required this.child,
    required this.control,
    this.maximized = false,
    super.key,
  });
  final String title;
  final Widget child;
  final bool maximized;
  final void Function(String) control;
  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    Widget button(String label, WindowGlyph icon, String command) => SizedBox(
      width: 44,
      height: 34,
      child: IconButton(
        tooltip: label,
        padding: EdgeInsets.zero,
        iconSize: 15,
        style: IconButton.styleFrom(
          shape: const RoundedRectangleBorder(),
          foregroundColor: tokens.colors.textSecondary,
          hoverColor: command == 'close'
              ? WindowCaptionPalette.closeHover
              : WindowCaptionPalette.hover,
        ).copyWith(side: const WidgetStatePropertyAll(BorderSide.none)),
        onPressed: () => control(command),
        icon: WindowControlIcon(icon),
      ),
    );
    return Scaffold(
      backgroundColor: tokens.surfaces.raised.fill,
      body: DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
          border: Border.all(
            color: tokens.surfaces.windowFrame,
            width: tokens.stroke.hairline,
          ),
        ),
        child: Column(
          children: [
            SizedBox(
              height: 34,
              child: Row(
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(left: 14),
                      child: Text(
                        title,
                        style: TextStyle(
                          fontSize: 12,
                          color: tokens.colors.textSecondary,
                        ),
                      ),
                    ),
                  ),
                  button('最小化', WindowGlyph.minimize, 'minimize'),
                  button(
                    maximized ? '还原' : '最大化',
                    maximized ? WindowGlyph.restore : WindowGlyph.maximize,
                    'toggleMaximize',
                  ),
                  button('关闭$title窗口', WindowGlyph.close, 'close'),
                ],
              ),
            ),
            Expanded(child: child),
          ],
        ),
      ),
    );
  }
}
