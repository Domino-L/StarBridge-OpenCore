import 'dart:convert';

import 'menu_profile_view.dart';

/// A bounded, current update for an already-open profile, never a new window.
({String window, int revision, MenuProfileView view})? parseMenuProfileUpdate(
  Object? arguments, {
  required bool enabled,
  required int opening,
  required Iterable<String> openWindows,
  required Map<String, int> revisions,
}) {
  if (!enabled ||
      arguments is! Map ||
      arguments['opening'] != opening ||
      arguments['revision'] is! int) {
    return null;
  }
  try {
    final payload = arguments['payload'];
    if (payload is! String || utf8.encode(payload).length > 1048576) {
      return null;
    }
    final view = jsonDecode(payload);
    if (view is! Map || view['window'] is! String) return null;
    final id = view['window'] as String;
    final revision = arguments['revision'] as int;
    if (!openWindows.contains(id) || revision <= (revisions[id] ?? -1)) {
      return null;
    }
    return (window: id, revision: revision, view: MenuProfileView.parse(view));
  } on Object {
    return null;
  }
}
