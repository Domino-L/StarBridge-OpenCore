import 'package:flutter/widgets.dart';

/// Logos the client already knows by organization code (SID), for places
/// that only carry a code, such as the personal page's affiliation. The
/// composition supplies it from the main fleet's own read; no request is
/// made here. Absent, or an unknown code, means no hint.
class OrganizationLogoHints extends InheritedNotifier<Listenable> {
  const OrganizationLogoHints({
    required Listenable super.notifier,
    required this.resolve,
    required super.child,
    super.key,
  });

  /// The logo URL for an upper-case organization code, or null.
  final String? Function(String code) resolve;

  static String? of(BuildContext context, String code) {
    final hints = context
        .dependOnInheritedWidgetOfExactType<OrganizationLogoHints>();
    final key = code.trim().toUpperCase();
    return hints == null || key.isEmpty ? null : hints.resolve(key);
  }
}
