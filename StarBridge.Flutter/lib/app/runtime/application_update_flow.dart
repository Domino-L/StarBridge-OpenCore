import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../features/settings/application_update_dialog.dart';
import '../../features/settings/application_update_status.dart';
import '../../platform/bridge/bridge_client_session.dart';
import 'startup_prompt_queue.dart';

/// Checks silently after entry; only a verified available update becomes a
/// queued secondary dialog. Consent/privacy/manual routes remain higher priority.
final class ApplicationUpdateFlow {
  ApplicationUpdateFlow({
    required this.session,
    required this.queue,
    required this.ready,
    required this.shownVersions,
    this.canPresent,
  });
  final BridgeClientSession session;
  final StartupPromptQueue queue;
  final bool Function() ready;
  final bool Function()? canPresent;
  final Set<String> shownVersions;
  final _key = Object();
  bool _disposed = false, _reading = false, _checked = false;
  int _attempts = 0;
  Timer? _retry;
  BridgeRequestOperation? _operation;
  VoidCallback? _dismiss;

  void wake() {
    if (_disposed ||
        _reading ||
        _checked ||
        _retry != null ||
        !ready() ||
        !session.hostCapabilities.contains('applicationUpdates.check')) {
      return;
    }
    unawaited(_read());
  }

  Future<void> _read() async {
    _reading = true;
    _attempts++;
    final generation = session.activeGeneration;
    try {
      _operation = session.beginRequest(
        'applicationUpdates.check',
        payload: const {'schemaVersion': 1},
        timeout: const Duration(seconds: 35),
      );
      final response = await _operation!.future;
      if (_disposed || session.activeGeneration != generation) return;
      final status = ApplicationUpdateStatus.parse(response.payload);
      if (status.state == 'channel-unavailable') {
        _scheduleRetry();
        return;
      }
      _checked = true;
      if (status.state != 'available') return;
      final version = status.version!;
      queue.enqueue(
        _key,
        priority: 150,
        eligible: () =>
            !_disposed &&
            ready() &&
            canPresent?.call() != false &&
            session.activeGeneration == generation,
        show: () async {
          if (_disposed ||
              shownVersions.contains(version) ||
              applicationUpdateShownVersions(session).contains(version)) {
            return;
          }
          final context = queue.navigator?.context;
          if (context == null) return;
          shownVersions.add(version);
          await showApplicationUpdateDialog(
            context,
            session,
            initialStatus: status,
            startupAnnouncement: true,
            isCurrent: () =>
                !_disposed && session.activeGeneration == generation,
            onDismissReady: (dismiss) => _dismiss = dismiss,
          );
          _dismiss = null;
        },
      );
    } on FormatException {
      _checked =
          true; // Invalid data is never presented or retried as an offer.
    } on BridgeClientException catch (error) {
      if (error.retryable) {
        _scheduleRetry();
      } else {
        _checked = true;
      }
    } on Object {
      _scheduleRetry();
    } finally {
      _reading = false;
      _operation = null;
    }
  }

  void _scheduleRetry() {
    if (_disposed || _attempts >= 3) {
      _checked = true;
      return;
    }
    _retry = Timer(Duration(seconds: _attempts == 1 ? 5 : 20), () {
      _retry = null;
      wake();
    });
  }

  void dispose() {
    _disposed = true;
    shownVersions.addAll(applicationUpdateShownVersions(session));
    _retry?.cancel();
    unawaited(_operation?.cancel());
    queue.cancel(_key);
    final dismiss = _dismiss;
    WidgetsBinding.instance.addPostFrameCallback((_) => dismiss?.call());
    if (dismiss != null) WidgetsBinding.instance.ensureVisualUpdate();
  }
}
