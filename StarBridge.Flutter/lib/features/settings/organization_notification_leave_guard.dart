import 'package:flutter/widgets.dart';

/// Mounted organization editors register here so navigation and application
/// close use the same unresolved-write guard. Account invalidation retires the
/// editor's request; merely leaving a page must not do so.
final _guards = <Future<bool> Function()>{};

void Function() registerOrganizationNotificationLeaveGuard(
  Future<bool> Function() guard,
) {
  _guards.add(guard);
  return () => _guards.remove(guard);
}

Future<bool> confirmOrganizationNotificationLeave() async {
  for (final guard in _guards.toList()) {
    if (_guards.contains(guard) && !await guard()) return false;
  }
  return true;
}

/// Section switches inside an organization page resolve a pending editor
/// first; the same check as leaving the page.
ValueChanged<T> guardedOrganizationSectionChange<T>(
  State<StatefulWidget> state,
  T Function() current,
  void Function(T) apply,
) => (value) async {
  if (value == current() || !await confirmOrganizationNotificationLeave()) {
    return;
  }
  if (state.mounted) apply(value);
};
