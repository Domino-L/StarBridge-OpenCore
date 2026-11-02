import 'package:flutter/widgets.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_overlay_text.dart';

dynamic resolvedMenuCopy(
  Object? value, [
  Locale locale = const Locale('zh', 'CN'),
]) => resolveMenuOverlayValue(value, AppStrings.resolve(locale));
