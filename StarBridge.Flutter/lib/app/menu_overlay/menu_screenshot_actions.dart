import 'package:flutter/material.dart';

import '../localization/app_strings.dart';
import '../../design_system/icons/standard_icon.dart';
import '../../design_system/icons/starbridge_icon.dart';
import '../../design_system/icons/icon_semantic.dart';
import 'menu_bridge_style.dart';
import 'menu_local_tools.dart' show MenuLocalToolsController;

/// The screenshot controls use the existing image toolbar's button styling and
/// disabled/crop guard. No separate file picker or image export implementation.
List<Widget> screenshotExportActions(
  BuildContext context,
  MenuLocalToolsController tools, {
  required bool available,
  required bool blocked,
  required Widget Function(String, Widget, VoidCallback?) button,
}) {
  String t(String key) => AppStrings.of(context).text('menu.screenshot.$key');
  return [
    button(
      t('captureSave'),
      const MenuGlyphView(MenuGlyph.camera, size: 16),
      !blocked && tools.screenshotDirectoryAvailable
          ? () => tools.captureAndSave(toDirectory: true)
          : null,
    ),
    button(
      t('copyAction'),
      const StandardIcon(StandardIconSemantic.copy, size: 16),
      available && !blocked ? () => tools.save(copy: true) : null,
    ),
    button(
      t('saveDirectoryAction'),
      const StarBridgeIcon(StarBridgeIconSemantic.save, size: 16),
      available && !blocked && tools.screenshotDirectoryAvailable
          ? () => tools.save(toDirectory: true)
          : null,
    ),
    button(
      t('saveAction'),
      const StarBridgeIcon(StarBridgeIconSemantic.save, size: 16),
      available && !blocked ? () => tools.save() : null,
    ),
  ];
}
