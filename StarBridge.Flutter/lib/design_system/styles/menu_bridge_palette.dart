import 'package:flutter/material.dart';

import '../tokens/starbridge_tokens.dart';

abstract final class BridgeInk {
  // Constant-only menu chrome mirrors the client dark tokens. Regression
  // tests compare these aliases against FutureRestraintStyle.
  static const text = Color(0xffe7eef2);
  static const muted = Color(0xff93a4ae);
  static const blue = Color(0xff4cb2f5);
  static const line = Color(0xff4c616e);
  static const green = Color(0xff3ed59a);
  static const amber = Color(0xfff5b544);
  static const danger = Color(0xfff26d75);
  static const ground = Color(0xff080c10);
  // Match client panel RGB; opacity is specific to the menu desktop.
  static const panel = Color(0xee111920);
  // Windows are reading surfaces, distinct from the translucent desktop chrome.
  static const window = Color(0xfa111920);
  static const divider = Color(0xff26333c);
  static const selected = Color(0xff173348);
  static const scrim = Color(0x85000000);
}

/// Reused menu controls inherit a light desktop theme, while the actual game
/// menu keeps its explicitly dark theme and original translucent palette.
class MenuBridgeColors {
  MenuBridgeColors.of(BuildContext context)
    : tokens = Theme.of(context).extension<StarBridgeTokens>(),
      highContrast = MediaQuery.highContrastOf(context);
  final StarBridgeTokens? tokens;
  final bool highContrast;
  bool get light => tokens?.isDark == false;
  Color get text => light ? tokens!.colors.textPrimary : BridgeInk.text;
  Color get muted => light ? tokens!.colors.textSecondary : BridgeInk.muted;
  Color get blue => highContrast
      ? text
      : light
      ? tokens!.colors.accent
      : BridgeInk.blue;
  Color get green => light ? tokens!.colors.success : BridgeInk.green;
  Color get amber => light ? tokens!.colors.warning : BridgeInk.amber;
  Color get danger => light ? tokens!.colors.danger : BridgeInk.danger;
  Color get line => highContrast
      ? text
      : light
      ? tokens!.surfaces.windowFrame
      : BridgeInk.line;
  Color get ground => light ? tokens!.surfaces.ground.fill : BridgeInk.ground;
  Color get panel => light ? tokens!.surfaces.panel.fill : BridgeInk.panel;
  Color get selected =>
      light ? tokens!.surfaces.selected.fill : BridgeInk.selected;
  Color get divider =>
      light ? tokens!.surfaces.panel.border : BridgeInk.divider;
}
