import 'dart:async';
import 'dart:convert';

import '../../features/common/user_interaction.dart';
import '../../features/personal_profile/personal_profile_port.dart';
import '../../features/personal_profile/personal_profile_models.dart';
import '../../platform/window/menu_profile_navigation.dart';
import 'menu_profile_view.dart';
import 'menu_profile_images.dart';

/// At most four independent read-only windows. Sources remain in the primary
/// engine; each owns cancelable reads and is retired on identity invalidation.
final class MenuProfilesSession implements MenuProfilesReadLease {
  MenuProfilesSession(this.createPort, this.publish, {this.createOwnPort});
  final PersonalProfilePort Function()? createOwnPort;
  final UserInteractionPort Function() createPort;
  final void Function(Map<String, Object?>) publish;
  final _windows = <String, _ProfileRead>{};
  bool _disposed = false;

  @override
  void open(String window, MenuProfileTarget target) {
    if (_disposed || !target.isCurrent() || _windows.containsKey(window)) {
      return;
    }
    if (_windows.length >= 4) {
      publish({'window': window, 'state': 'unavailable'});
      return;
    }
    final entry = _ProfileRead(target);
    _windows[window] = entry;
    entry.timer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => refresh(window),
    );
    refresh(window);
  }

  @override
  void refresh(String window) {
    final entry = _windows[window];
    if (_disposed || entry == null || entry.reading) return;
    if (!entry.target.isAccountCurrent()) {
      _revoke(window);
      return;
    }
    unawaited(_read(window, entry));
  }

  Future<void> _read(String window, _ProfileRead entry) async {
    entry.reading = true;
    final revision = ++entry.revision;
    try {
      await entry.releasePort();
      if (_disposed || !identical(_windows[window], entry)) return;
      final self = entry.target.source == 'self';
      if (self && createOwnPort == null) throw StateError('unsupported');
      final port = self ? null : (entry.port = createPort());
      final ownPort = self ? (entry.ownPort = createOwnPort!()) : null;
      void revoke() {
        if (identical(_windows[window], entry) &&
            identical(entry.port, port) &&
            identical(entry.ownPort, ownPort)) {
          _revoke(window);
        }
      }

      entry.subscription = (ownPort?.invalidations ?? port!.invalidations)
          .listen((_) => revoke(), onDone: revoke);
      // Polling revalidates authority without unmounting the visible document.
      if (!entry.ready) publish({'window': window, 'state': 'loading'});
      final target = entry.target;
      final reference = self || target.refreshReference == null
          ? target.reference
          : await target.refreshReference!().timeout(
              const Duration(seconds: 15),
            );
      if (_disposed || !identical(_windows[window], entry)) return;
      if (!target.isAccountCurrent()) {
        _revoke(window);
        return;
      }
      final snapshot =
          await (ownPort != null
                  ? ownPort.read()
                  : port!.profile(
                      UserTarget(
                        target.source,
                        reference,
                        query: target.query,
                        contextRef: target.contextRef,
                      ),
                    ))
              .timeout(const Duration(seconds: 15));
      if (_disposed || !identical(_windows[window], entry)) return;
      if (!target.isAccountCurrent()) {
        _revoke(window);
        return;
      }
      final view = self
          ? MenuProfileView.encodeSelf(snapshot, avatar: target.avatar)
          : MenuProfileView.encode(snapshot, avatar: target.avatar);
      entry.ready = view['state'] == 'ready';
      if (view['state'] != 'ready') entry.images.clear();
      final affiliations = (view['affiliations'] as List?)
          ?.map((row) => Map<String, Object?>.of(row as Map<String, Object?>))
          .toList();
      var remaining = 900000 - utf8.encode(jsonEncode(view)).length;
      bool attach(int index, String? image) {
        if (image == null || affiliations![index]['image'] == image) {
          return false;
        }
        final delta =
            jsonEncode(image).length -
            jsonEncode(affiliations[index]['image']).length;
        if (delta > remaining) return false;
        remaining -= delta;
        affiliations[index]['image'] = image;
        return true;
      }

      if (affiliations != null) {
        for (var i = 0; i < affiliations.length; i++) {
          final a = snapshot.affiliations[i];
          attach(
            i,
            entry.images.cached(a.logoImageData) ??
                (affiliations[i]['image'] as String?) ??
                entry.images.cached(a.logoUrl),
          );
        }
      }
      void emit() => publish({
        'window': window,
        ...view,
        if (affiliations != null)
          'affiliations': [
            for (final row in affiliations) {...row},
          ],
      });
      emit();
      if (affiliations != null) {
        unawaited(_loadImages(window, entry, revision, snapshot, attach, emit));
      }
    } on Object {
      entry.ready = false;
      await entry.releasePort();
      entry.images.clear();
      if (!_disposed && identical(_windows[window], entry)) {
        publish({'window': window, 'state': 'unavailable'});
      }
    } finally {
      // Successful reads retain their identity-invalidation listener.
      entry.reading = false;
    }
  }

  Future<void> _loadImages(
    String window,
    _ProfileRead entry,
    int revision,
    PersonalProfileSnapshot snapshot,
    bool Function(int, String?) attach,
    void Function() emit,
  ) async {
    await Future.wait([
      for (var i = 0; i < snapshot.affiliations.length; i++)
        () async {
          final a = snapshot.affiliations[i];
          var image = await entry.images.load(a.logoImageData);
          if (_disposed ||
              !identical(_windows[window], entry) ||
              entry.revision != revision ||
              !entry.target.isAccountCurrent()) {
            return;
          }
          image ??= await entry.images.load(a.logoUrl);
          if (_disposed ||
              !identical(_windows[window], entry) ||
              entry.revision != revision) {
            return;
          }
          if (!entry.target.isAccountCurrent()) {
            _revoke(window);
            return;
          }
          if (attach(i, image)) {
            emit();
          }
        }(),
    ]);
  }

  void _revoke(String window) {
    if (!_windows.containsKey(window)) return;
    closeWindow(window);
    if (!_disposed) publish({'window': window, 'state': 'revoked'});
  }

  @override
  void closeWindow(String window) {
    final entry = _windows.remove(window);
    entry?.timer?.cancel();
    entry?.images.dispose();
    if (entry != null) unawaited(entry.releasePort());
  }

  @override
  void hide() {
    for (final id in _windows.keys.toList()) {
      closeWindow(id);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    hide();
  }
}

final class _ProfileRead {
  _ProfileRead(this.target);
  final MenuProfileTarget target;
  UserInteractionPort? port;
  PersonalProfilePort? ownPort;
  StreamSubscription<void>? subscription;
  Timer? timer;
  bool reading = false;
  bool ready = false;
  int revision = 0;
  final images = MenuProfileImages();
  Future<void> releasePort() async {
    final old = port, oldSubscription = subscription;
    final oldOwn = ownPort;
    ownPort = null;
    port = null;
    subscription = null;
    // Retire delivery first, but start transport cancellation synchronously.
    final canceled = oldSubscription?.cancel();
    final closed = old?.close();
    final ownClosed = oldOwn?.close();
    await canceled;
    await closed;
    await ownClosed;
  }
}
