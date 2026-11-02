import 'package:flutter/widgets.dart';
import 'package:flutter/foundation.dart';

import '../design_system/icons/icon_semantic.dart';
import 'routing/coming_soon_destination.dart';
export '../design_system/icons/icon_semantic.dart';

enum FeatureAvailability { available, comingSoon }

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

/// What the sidebar shows when its attention count is hovered or focused
/// (0.7.2, approved option C): a breakdown card. [open] opens the feature the
/// same way its navigation item does; [describe] is what a reader announces
/// instead of the bare number.
class AttentionDetail {
  const AttentionDetail({
    required this.build,
    required this.describe,
    required this.listenable,
  });
  final Widget Function(BuildContext context, VoidCallback open) build;
  final String Function(BuildContext context) describe;
  final Listenable listenable;
}
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
    DestinationBuilder? buildDestination,
    this.availability = FeatureAvailability.available,
    this.navigationParentId,
    this.confirmLeave,
    this.attentionCount,
    this.attentionDetail,
    this.buildNavigationPanel,
    this.onPrimaryNavigation,
    this.onSearchShortcut,
    this.primaryNavigationSelected,
    this.prefetch,
    this.onDispose,
    this.openSection,
  }) : assert(
         availability == FeatureAvailability.comingSoon ||
             buildDestination != null,
       ),
       _buildDestination = buildDestination;

  final String id;
  final String route;
  final String labelKey;
  final String descriptionKey;
  final StarBridgeIconSemantic icon;
  final NavigationRegion navigationRegion;
  final int order;
  final FeatureAvailability availability;
  final DestinationBuilder? _buildDestination;
  DestinationBuilder get buildDestination =>
      availability == FeatureAvailability.comingSoon
      ? (_) => ComingSoonDestination(
          destinationKey: id,
          icon: icon,
          featureKey: labelKey,
        )
      : _buildDestination!;
  final String? navigationParentId;
  final DestinationLeaveGuard? confirmLeave;
  final ValueListenable<int>? attentionCount;
  final AttentionDetail? attentionDetail;
  final NavigationPanelBuilder? buildNavigationPanel;
  // A feature with child destinations may give its primary item a distinct
  // landing action and selection state, without changing shortcut activation.
  final Future<void> Function()? onPrimaryNavigation;

  /// What the global search shortcut (Ctrl+K) does after opening this
  /// destination. Kept apart from [onPrimaryNavigation] so an ordinary visit
  /// never grabs focus for a search the user did not ask for.
  final Future<void> Function()? onSearchShortcut;
  final ValueListenable<bool>? primaryNavigationSelected;

  /// Optional, bounded read only. Must not activate a destination or mutate data.
  final Future<void> Function()? prefetch;

  /// Release resources owned by this registration when its registry retires.
  /// Route changes do not retire the registration. Borrowed resources stay owned
  /// by their original composition and must not be disposed by this callback.
  final VoidCallback? onDispose;

  /// A part of the destination a route asks for with `?section=` (a
  /// notification opening 我的交易 or 交易消息). The shell calls it before
  /// selecting the destination; unknown sections are ignored.
  final void Function(String section)? openSection;

  bool ownsNavigationSelection(FeatureDescriptor selected) =>
      identical(this, selected) || selected.navigationParentId == id;
}

final class FeatureRegistry {
  FeatureRegistry(Iterable<FeatureDescriptor> descriptors)
    : _descriptors = List.unmodifiable(descriptors) {
    _validate();
  }

  final List<FeatureDescriptor> _descriptors;
  bool _disposed = false;

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final descriptor in _descriptors) {
      descriptor.onDispose?.call();
    }
  }

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
