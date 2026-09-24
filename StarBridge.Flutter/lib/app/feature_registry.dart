import 'package:flutter/widgets.dart';
import 'package:flutter/foundation.dart';

import '../design_system/icons/icon_semantic.dart';
export '../design_system/icons/icon_semantic.dart';

enum NavigationRegion {
  brand,
  primary,
  personal,
  topBar,
  accountMenu,
  shortcut,
}

typedef NavigationPanelBuilder = Widget Function(
  BuildContext context,
  bool iconOnly,
  bool selected,
  Future<bool> Function() activate,
);

typedef DestinationBuilder = Widget Function(BuildContext context);
typedef DestinationLeaveGuard = Future<bool> Function(BuildContext context);

final class FeatureDescriptor {
  const FeatureDescriptor({
    required this.id,
    required this.route,
    required this.labelKey,
    required this.descriptionKey,
    required this.icon,
    required this.navigationRegion,
    required this.order,
    required this.buildDestination,
    this.navigationParentId,
    this.confirmLeave,
    this.attentionCount,
    this.buildNavigationPanel,
    this.onPrimaryNavigation,
    this.primaryNavigationSelected,
    this.prefetch,
  });

  final String id;
  final String route;
  final String labelKey;
  final String descriptionKey;
  final StarBridgeIconSemantic icon;
  final NavigationRegion navigationRegion;
  final int order;
  final DestinationBuilder buildDestination;
  final String? navigationParentId;
  final DestinationLeaveGuard? confirmLeave;
  final ValueListenable<int>? attentionCount;
  final NavigationPanelBuilder? buildNavigationPanel;
  // A feature with child destinations may give its primary item a distinct
  // landing action and selection state, without changing shortcut activation.
  final Future<void> Function()? onPrimaryNavigation;
  final ValueListenable<bool>? primaryNavigationSelected;

  /// Optional, bounded read only. Must not activate a destination or mutate data.
  final Future<void> Function()? prefetch;

  bool ownsNavigationSelection(FeatureDescriptor selected) =>
      identical(this, selected) || selected.navigationParentId == id;
}

final class FeatureRegistry {
  FeatureRegistry(Iterable<FeatureDescriptor> descriptors)
    : _descriptors = List.unmodifiable(descriptors) {
    _validate();
  }

  final List<FeatureDescriptor> _descriptors;

  List<FeatureDescriptor> get all => _descriptors;

  FeatureDescriptor get home => _descriptors.singleWhere(
    (item) => item.navigationRegion == NavigationRegion.brand,
  );

  FeatureDescriptor byRoute(String route) =>
      _descriptors.singleWhere((item) => item.route == route);

  List<FeatureDescriptor> inRegion(NavigationRegion region) {
    final result = _descriptors
        .where((item) => item.navigationRegion == region)
        .toList();
    result.sort((left, right) => left.order.compareTo(right.order));
    return List.unmodifiable(result);
  }

  void _validate() {
    _requireUnique(_descriptors.map((item) => item.id), 'feature ID');
    _requireUnique(_descriptors.map((item) => item.route), 'route');
    if (_descriptors
            .where((item) => item.navigationRegion == NavigationRegion.brand)
            .length !=
        1) {
      throw StateError(
        'Feature registry must contain exactly one brand/home destination.',
      );
    }
    final knownIds = _descriptors.map((item) => item.id).toSet();
    for (final descriptor in _descriptors) {
      final parentId = descriptor.navigationParentId;
      if (parentId != null && !knownIds.contains(parentId)) {
        throw StateError(
          'Feature ${descriptor.id} references unknown navigation parent '
          '$parentId.',
        );
      }
    }
  }

  static void _requireUnique(Iterable<String> values, String label) {
    final seen = <String>{};
    for (final value in values) {
      if (value.isEmpty || !seen.add(value)) {
        throw StateError(
          'Feature registry contains an empty or duplicate $label: $value',
        );
      }
    }
  }
}
