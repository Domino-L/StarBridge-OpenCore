import 'dart:async';
import 'dart:ui' show Locale;

import 'package:flutter/services.dart';

import 'menu_feature_view.dart';

/// Display-only feature messages and resource retirement. A resource epoch
/// never grants visibility, an action, or a new opening/account lease.
final class MenuSurfaceFeatures {
  MenuSurfaceFeatures({
    required this.features,
    required this.revisions,
    required this.visible,
    required this.timers,
    required this.opening,
    required this.wanted,
    required this.enabled,
    required this.update,
    this.locale,
  });
  final Map<String, MenuFeatureView> features;
  final Map<String, int> revisions;
  final Set<String> visible;
  final Map<String, Timer> timers;
  final int Function() opening;
  final bool Function() wanted, enabled;
  final void Function(void Function()) update;
  final Locale Function()? locale;
  int _epoch = 0;
  static const maxEpoch = 9007199254740991;

  bool adopt(Object? value) {
    if (value is! int || value < 0 || value > maxEpoch) return false;
    if (value > _epoch) {
      _epoch = value;
      features.updateAll(
        (tool, view) =>
            tool == 'organizations' ? view.withoutOrganizationImages() : view,
      );
    }
    return true;
  }

  Map<String, Object?> retire(Object? raw) {
    if (raw is! Map ||
        raw.length != 2 ||
        raw['schemaVersion'] != 1 ||
        raw['resourceEpoch'] is! int ||
        (raw['resourceEpoch'] as int) <= 0 ||
        (raw['resourceEpoch'] as int) > maxEpoch) {
      throw PlatformException(code: 'menu.invalidImageMaintenance');
    }
    update(() => adopt(raw['resourceEpoch']));
    return {'schemaVersion': 1, 'resourceEpoch': _epoch};
  }

  void accept(MethodCall call) {
    final data = call.arguments;
    if (data is! Map ||
        !wanted() ||
        !enabled() ||
        data['opening'] != opening() ||
        data['revision'] is! int) {
      return;
    }
    final entry = MenuFeatureView.envelope(
      data['payload'],
      locale: locale?.call(),
    );
    if (entry == null ||
        !visible.contains(entry.$1) ||
        (data['revision'] as int) <= (revisions[entry.$1] ?? -1)) {
      return;
    }
    final epoch = data['resourceEpoch'] ?? 0;
    timers.remove(entry.$1)?.cancel();
    update(() {
      revisions[entry.$1] = data['revision'] as int;
      features[entry.$1] = epoch == _epoch || entry.$1 != 'organizations'
          ? entry.$2
          : entry.$2.withoutOrganizationImages();
    });
  }
}
