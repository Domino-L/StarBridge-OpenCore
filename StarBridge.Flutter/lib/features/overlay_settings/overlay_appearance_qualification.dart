import 'package:flutter/widgets.dart';

/// Whether this client currently has no entitlement facts to judge by. It says
/// nothing about what the account owns, so the page must not call an appearance
/// locked while this is true. Absent means the facts are as read.
final class OverlayAppearanceQualification extends InheritedWidget {
  const OverlayAppearanceQualification({
    required this.unknown,
    required super.child,
    super.key,
  });

  final bool unknown;

  static bool unknownOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<OverlayAppearanceQualification>()
          ?.unknown ??
      false;

  @override
  bool updateShouldNotify(OverlayAppearanceQualification oldWidget) =>
      unknown != oldWidget.unknown;
}
