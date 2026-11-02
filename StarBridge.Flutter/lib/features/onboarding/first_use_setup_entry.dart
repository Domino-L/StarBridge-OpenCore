import 'package:flutter/widgets.dart';

import '../../shared/release/official_client_profile.dart';

/// Borrows the primary window's setup route. It owns no account or data.
final class FirstUseSetupEntry extends InheritedWidget {
  const FirstUseSetupEntry({
    required this.open,
    required super.child,
    super.key,
  });
  final Future<void> Function(BuildContext)? open;
  static Future<void> Function(BuildContext)? of(BuildContext context) =>
      OfficialClientProfile.firstUseGuide
      ? context.dependOnInheritedWidgetOfExactType<FirstUseSetupEntry>()?.open
      : null;
  @override
  bool updateShouldNotify(FirstUseSetupEntry oldWidget) =>
      oldWidget.open != open;
}
