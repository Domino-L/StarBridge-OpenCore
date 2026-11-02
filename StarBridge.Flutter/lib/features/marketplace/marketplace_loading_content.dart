import 'package:flutter/widgets.dart';

import '../../shared/diagnostics/loading_content_probe.dart';
import '../../shared/diagnostics/loading_metrics.dart';
import 'marketplace_controller.dart';
import 'marketplace_port.dart';

/// Measures the selected surface's primary content, not image completion,
/// reputation, watch-list prices, hidden tabs or background request activity.
/// The existing paint probe still requires an active route and engine raster.
class MarketplaceLoadingContent extends StatelessWidget {
  const MarketplaceLoadingContent({
    required this.controller,
    required this.child,
    super.key,
  });

  final MarketplaceController controller;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final metrics = LoadingMetrics.current;
    if (metrics == null || metrics.stopped) return child;
    return ListenableBuilder(
      // The parent already observes the controller. Browser reads independently
      // notify their existing owner without rebuilding that parent.
      listenable: controller.browser,
      builder: (context, _) {
        final content = _selected(controller);
        return LoadingContentProbe(
          route: '/marketplace',
          status: content.$1,
          items: content.$2,
          child: child,
        );
      },
    );
  }
}

typedef _Content = (LoadingContentStatus, int);

_Content _read(
  MarketRead? read,
  bool failed, {
  bool identity = false,
  int? items,
}) {
  if (read == null) {
    return (
      failed ? LoadingContentStatus.unavailable : LoadingContentStatus.waiting,
      0,
    );
  }
  final count = items ?? (identity ? 1 : read.rows.length);
  return (
    failed
        ? LoadingContentStatus.partial
        : count == 0
        ? LoadingContentStatus.empty
        : LoadingContentStatus.data,
    count,
  );
}

_Content _selected(MarketplaceController c) {
  if (c.mainTab == 1 && !c.hasItem) {
    return _read(c.browser.result, c.browser.failed);
  }
  if (c.mainTab != 0) return (LoadingContentStatus.unavailable, 0);
  _Content block(String key, {bool identity = false}) =>
      _read(c.blocks[key], c.failures.contains(key), identity: identity);
  if (c.hasItem) {
    return _combine([
      block('item', identity: true),
      block(['sell', 'buy', 'trend', 'acquisition'][c.itemTab]),
    ]);
  }
  if (c.hasCatalog) return block('catalog');
  final categories = c.blocks['categories'];
  return _combine([
    _read(
      categories,
      c.failures.contains('categories'),
      // Match the root tiles the hall actually constructs, not hidden children.
      items: categories?.rows
          .where((row) => row['parentId'] == 0 || row['parentId'] == null)
          .length,
    ),
    block('trending'),
    block('latest'),
  ]);
}

_Content _combine(List<_Content> parts) {
  final count = parts.fold(0, (total, part) => total + part.$2);
  final states = parts.map((part) => part.$1).toSet();
  const complete = {LoadingContentStatus.data, LoadingContentStatus.empty};
  if (states.every(complete.contains)) {
    return (
      count == 0 ? LoadingContentStatus.empty : LoadingContentStatus.data,
      count,
    );
  }
  if (states.any(complete.contains) ||
      states.contains(LoadingContentStatus.partial)) {
    return (LoadingContentStatus.partial, count);
  }
  return (
    states.contains(LoadingContentStatus.waiting)
        ? LoadingContentStatus.waiting
        : LoadingContentStatus.unavailable,
    count,
  );
}
