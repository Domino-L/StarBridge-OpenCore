import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../platform/bridge/bridge_client_session.dart';
import 'hangar_reader_port.dart';
import 'hangar_arrival_timeline.dart';

/// Presentation/lifecycle only. Host owns identity, completeness and result facts.
final class HangarReaderController extends ChangeNotifier {
  HangarReaderController(
    this.browser,
    this.preview, {
    this.pollInterval = const Duration(milliseconds: 600),
    this.pageTimeout = const Duration(seconds: 60),
  });
  final HangarBrowserPort browser;
  final HangarPreviewPort preview;
  final Duration pollInterval;
  final Duration pageTimeout;
  String phase = 'idle';
  Map<String, Object?> view = const {};
  final arrivals = HangarArrivalTimeline();
  bool browserOpen = false;
  int browserRevision = 0;
  bool _disposed = false;
  int _epoch = 0;
  bool _working = false;
  bool get canAct => !_working && !_disposed;
  bool get busy =>
      ['opening', 'starting', 'reading', 'verifying'].contains(phase);
  bool get paused =>
      ['awaitingIdentity', 'loginRequired', 'emptyUnconfirmed'].contains(phase);

  void _set(String value) {
    if (!_disposed) {
      phase = value;
      arrivals.accept(view, phase: value);
      notifyListeners();
    }
  }

  bool _current(int epoch) => !_disposed && epoch == _epoch;
  Future<void> open() async {
    if (busy || !canAct) return;
    _working = true;
    final epoch = ++_epoch;
    browserOpen = false;
    view = const {};
    _set('opening');
    try {
      await preview.cancel();
      if (!_current(epoch)) return;
      await browser.close();
      if (!_current(epoch)) return;
      final profileKey = await preview.prepare();
      if (!_current(epoch)) return;
      await browser.open(profileKey: profileKey);
      if (!_current(epoch)) {
        await browser.close();
        return;
      }
      browserOpen = true;
      browserRevision++;
      _set('ready');
    } on Object catch (error) {
      if (_current(epoch)) {
        await browser.close();
        _set(_failure(error));
      }
    } finally {
      _working = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> read() async {
    if (busy || !browserOpen || !canAct) return;
    _working = true;
    final epoch = ++_epoch;
    _set('starting');
    try {
      final loading = Stopwatch()..start();
      Map<String, Object?>? identity;
      while (_current(epoch)) {
        try {
          // Lock before the sole identity capture; never navigate away from the open avatar first.
          identity = await browser.lock();
          break;
        } on HangarReaderFailure catch (error) {
          if (error.code != 'loading') rethrow;
          if (loading.elapsed >= pageTimeout) {
            throw const HangarReaderFailure('timedOut');
          }
          await Future<void>.delayed(pollInterval);
        }
      }
      if (!_current(epoch)) return;
      final begun = await preview.begin();
      if (!_current(epoch)) return;
      view = begun;
      final verified = await preview.verify(identity!);
      if (!_current(epoch)) return;
      view = verified;
      if (view['phase'] != 'reading') {
        _set(view['phase'] as String? ?? 'failed');
        return;
      }
      await browser.page(1);
      if (!_current(epoch)) return;
      _set('reading');
      final clock = Stopwatch()..start();
      var pageStarted = Duration.zero;
      while (_current(epoch)) {
        if (clock.elapsed - pageStarted > pageTimeout ||
            clock.elapsed > const Duration(minutes: 10)) {
          throw const HangarReaderFailure('timedOut');
        }
        Map<String, Object?> observed;
        try {
          observed = await browser.capture();
        } on HangarReaderFailure catch (error) {
          if (error.code != 'loading') rethrow;
          await Future<void>.delayed(pollInterval);
          continue;
        }
        if (!_current(epoch)) return;
        final result = await preview.observe(observed);
        if (!_current(epoch)) return;
        final oldPage = view['expectedPage'];
        view = result;
        _set(result['phase'] as String? ?? 'failed');
        if (!['reading', 'verifying'].contains(phase)) return;
        if (result['expectedPage'] != oldPage) {
          await browser.page(result['expectedPage'] as int);
          pageStarted = clock.elapsed;
        }
        await Future<void>.delayed(pollInterval);
      }
    } on Object catch (error) {
      if (_current(epoch)) _set(_failure(error));
    } finally {
      // Returning control ends the scan binding. Retrying always checks identity anew.
      try {
        await browser.unlock();
      } on Object {
        await browser.close();
        browserOpen = false;
      }
      // A frozen, verified result may be confirmed locally after the browser
      // lock ends. Leaving, cancellation or account changes still discard it.
      if (!_current(epoch) ||
          !['complete', 'needsReview'].contains(phase) ||
          view['canSave'] != true) {
        await preview.cancel();
      }
      _working = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> cancel({String reason = 'cancelled'}) async {
    ++_epoch;
    browserOpen = false;
    if (reason == 'accountChanged') view = const {};
    _set(reason);
    await Future.wait([browser.close(), preview.cancel()]);
  }

  static String _failure(Object error) {
    if (error is HangarReaderFailure) return error.code;
    if (error is TimeoutException || error is BridgeTimeoutException) {
      return 'timedOut';
    }
    if (error is BridgeRemoteException) {
      if (error.code == 'hangar.identity_unavailable') {
        return 'identityUnavailable';
      }
      if (error.code == 'bridge.capability_unavailable') {
        return 'hostUnavailable';
      }
    }
    return 'failed';
  }

  @override
  void dispose() {
    _disposed = true;
    ++_epoch;
    unawaited(browser.close());
    unawaited(preview.cancel());
    super.dispose();
  }
}
