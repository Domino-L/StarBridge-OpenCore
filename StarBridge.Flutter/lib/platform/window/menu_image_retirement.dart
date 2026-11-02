import 'package:flutter/services.dart';

import '../../shared/downloadable_image_cache.dart';
import 'method_channel_menu_window_lifetime.dart';

/// A bounded, display-only control for an existing engine. It never creates,
/// reveals or focuses a window, or sends a business/account snapshot.
final class MenuImageRetirement
    implements DownloadableImageCache, ImageCacheMaintenanceBarrier {
  MenuImageRetirement(
    this.lifetime,
    this.channel, {
    required this.isCurrent,
    required this.request,
  });
  final MenuWindowLifetime lifetime;
  final MethodChannel channel;
  final bool Function() isCurrent;
  final int? Function() request;
  final _pending = <Future<({Object? error, StackTrace? stack})>>[];

  void _advance() {
    final epoch = lifetime.nextImageEpoch();
    if (!isCurrent()) return;
    final owner = request();
    _pending.add(
      _send(epoch, owner).then<({Object? error, StackTrace? stack})>(
        (_) => (error: null, stack: null),
        onError: (Object error, StackTrace stack) =>
            (error: error, stack: stack),
      ),
    );
  }

  Future<void> _send(int epoch, int? owner) async {
    final reply = await channel
        .invokeMethod<Object?>('imageMaintenance', {
          'schemaVersion': 1,
          'resourceEpoch': epoch,
          'request': ?owner,
        })
        .timeout(const Duration(seconds: 3));
    if (reply is! Map ||
        reply.length != 3 ||
        reply['schemaVersion'] != 1 ||
        reply['resourceEpoch'] is! int ||
        (reply['resourceEpoch'] as int) < epoch ||
        (reply['resourceEpoch'] as int) > 9007199254740991 ||
        reply['enginePresent'] is! bool) {
      throw StateError('Unconfirmed menu image retirement');
    }
  }

  @override
  void beginImageMaintenance() => _advance();
  @override
  void endImageMaintenance() => _advance();
  @override
  Future<void> get imageMaintenanceSettled async {
    final waiting = List.of(_pending);
    _pending.clear();
    final receipts = await Future.wait(waiting);
    for (final receipt in receipts) {
      if (receipt.error != null) {
        Error.throwWithStackTrace(receipt.error!, receipt.stack!);
      }
    }
  }
}
