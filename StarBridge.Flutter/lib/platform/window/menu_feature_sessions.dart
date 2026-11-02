import '../../shared/downloadable_image_cache.dart';
import 'menu_feature_lease.dart';

/// Owns only sessions already requested by the menu. Maintenance never creates
/// a session or changes visibility; a late-created session inherits its phase.
final class MenuFeatureSessions
    implements DownloadableImageCache, ImageCacheMaintenanceBarrier {
  MenuFeatureSessions(this.factories, this.publish, {this.retirement});
  final DownloadableImageCache? retirement;
  @override
  Future<void> get imageMaintenanceSettled =>
      retirement is ImageCacheMaintenanceBarrier
      ? (retirement as ImageCacheMaintenanceBarrier).imageMaintenanceSettled
      : Future.value();
  final Map<String, MenuFeatureFactory> factories;
  final void Function(Map<String, Object?>) publish;
  final _leases = <String, MenuFeatureLease>{};
  bool _paused = false, _closed = false;
  Map<String, MenuFeatureLease> get current => Map.unmodifiable(_leases);
  Iterable<MenuFeatureLease> get values => _leases.values;
  MenuFeatureLease? operator [](String tool) => _leases[tool];

  MenuFeatureLease obtain(String tool) {
    if (_closed) throw StateError('Menu sessions disposed');
    return _leases.putIfAbsent(tool, () {
      final lease = factories[tool]!(
        (view) => publish({...view, 'tool': tool}),
      );
      try {
        if (_paused && lease is DownloadableImageCache) {
          (lease as DownloadableImageCache).beginImageMaintenance();
        }
      } on Object {
        lease.dispose();
        rethrow;
      }
      return lease;
    });
  }

  @override
  void beginImageMaintenance() {
    if (_closed) return;
    _paused = true;
    retirement?.beginImageMaintenance();
    _visit((cache) => cache.beginImageMaintenance());
  }

  @override
  void endImageMaintenance() {
    if (_closed) return;
    _paused = false;
    retirement?.endImageMaintenance();
    _visit((cache) => cache.endImageMaintenance());
  }

  void _visit(void Function(DownloadableImageCache) action) {
    Object? failure;
    StackTrace? trace;
    for (final lease in _leases.values.toList()) {
      if (lease is! DownloadableImageCache) continue;
      try {
        action(lease as DownloadableImageCache);
      } catch (error, stack) {
        failure ??= error;
        trace ??= stack;
      }
    }
    if (failure != null) Error.throwWithStackTrace(failure, trace!);
  }

  void dispose() {
    if (_closed) return;
    _closed = true;
    for (final lease in _leases.values) {
      lease.dispose();
    }
    _leases.clear();
  }
}
