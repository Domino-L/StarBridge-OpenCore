import 'dart:async';

import 'privacy_publication_port.dart';

/// Keeps the shell status light current. Without Host change events the
/// status is polled every 5 s; with them it is re-read on change and a slow
/// timer only covers a missed event.
final class PrivacyPublicationMonitor {
  PrivacyPublicationMonitor(this._port, this._read);

  static const pollInterval = Duration(seconds: 5);
  static const eventFallbackInterval = Duration(seconds: 60);
  static const eventCoalescing = Duration(milliseconds: 300);

  final Object _port;
  final void Function() _read;
  Timer? _timer, _delay;
  StreamSubscription<void>? _changes;

  bool get eventsSupported {
    final port = _port;
    return port is PrivacyPublicationChangePort &&
        port.publicationEventsSupported;
  }

  void start() {
    final port = _port;
    final events =
        port is PrivacyPublicationChangePort && port.publicationEventsSupported;
    if (port is PrivacyPublicationChangePort && events) {
      _changes ??= port.publicationChanges.listen((_) {
        // Coalesce bursts (each successful publish changes AppliedAt).
        if (_timer == null || (_delay?.isActive ?? false)) return;
        _delay = Timer(eventCoalescing, _read);
      });
    }
    _timer ??= Timer.periodic(
      events ? eventFallbackInterval : pollInterval,
      (_) => _read(),
    );
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _delay?.cancel();
    _delay = null;
    unawaited(_changes?.cancel());
    _changes = null;
  }
}
