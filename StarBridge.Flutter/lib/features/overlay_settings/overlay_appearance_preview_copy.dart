import 'package:flutter/widgets.dart';

import '../../app/localization/app_strings.dart';
import 'overlay_workspace_schema.dart';

String overlayAppearancePreviewText(
  BuildContext context,
  String cn,
  String tw,
  String en,
) {
  final locale = Localizations.localeOf(context);
  return locale.languageCode != 'zh'
      ? en
      : locale.scriptCode == 'Hant' || locale.countryCode == 'TW'
      ? tw
      : cn;
}

String overlayAppearancePreviewFieldName(BuildContext context, String field) {
  final key = 'overlay.workspace.field.$field';
  final text = AppStrings.of(context).text(key);
  return text == key
      ? overlayWorkspaceFieldSpecs.singleWhere((f) => f.field == field).labelZh
      : text;
}
