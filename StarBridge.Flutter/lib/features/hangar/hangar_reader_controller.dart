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

  /// Remember the RSI sign-in on this computer. Null until read from native;
  /// anything but an explicit yes is treated as not remembering.
  bool? remember;

  /// A clear did not finish, so RSI sign-in data may remain on this computer.
  bool uncleared = false;

  /// The saved choice could not be read, so nothing is cleared for now.
  bool unknown = false;

  /// Why the last change of the choice failed, shown beside the choice.
  String? choiceError;
  bool _disposed = false;
  int _epoch = 0;
  bool _working = false;
  bool get canAct => !_working && !_disposed;
  bool get busy => [
    'opening',
    'starting',
    'reading',
    'verifying',
    'clearing',
  ].contains(phase);
  bool get paused =>
      ['awaitingIdentity', 'loginRequired', 'emptyUnconfirmed'].contains(phase);

  /// Stops where the next step is the user's, inside the open RSI page. The
  /// page stays open here even when the sign-in is not remembered, so an
  /// emailed verification code is not asked for again.
  static const _inPageSteps = {
    'awaitingIdentity',
    'loginRequired',
    'navigation',
    'emptyUnconfirmed',
    'filtered',
  };

  /// Native owns the choice and knows whether every clear finished.
  Future<void> refreshSignIn() async {
    try {
      final state = await browser.readSignIn();
      if (_disposed) return;
      remember = state.remember;
      uncleared = state.uncleared;
      unknown = state.unknown;
    } on Object {
      if (_disposed) return;
      remember ??= false;
    }
    notifyListeners();
  }

  /// Changing the choice closes the open page: it belongs to the old choice.
  /// Not remembering also clears what was remembered. An open page reopens
  /// under the new choice, so the user signs in once more.
  Future<void> setRemember(bool value) async {
    if (busy || !canAct || value == remember) return;
    _working = true;
    final epoch = ++_epoch;
    final reopen = browserOpen;
    // Finished results stay on screen; the change happens beside them.
    final results = ['complete', 'needsReview'].contains(phase);
    browserOpen = false;
    if (!results) _set(value ? 'opening' : 'clearing');
    var changed = false;
    try {
      await browser.setRemember(value);
      changed = true;
      remember = value;
      choiceError = null;
      if (_current(epoch) && !results) {
        // Reopening below starts from rest.
        _set(!reopen && !value ? 'forgotten' : 'idle');
      }
    } on Object catch (error) {
      final code = error is HangarReaderFailure ? error.code : 'choice_failed';
      final clearing = [
        'clear_busy',
        'clear_unsafe',
        'clear_failed',
      ].contains(code);
      choiceError = clearing ? code : 'choice_failed';
      if (clearing) {
        // The choice was saved; only the clearing failed. Close what may
        // still be open; the failure stays reported until a clear succeeds.
        remember = value;
        try {
          await browser.close();
        } on Object {
          // Reported through the native clear status below.
        }
      } else {
        // Nothing changed natively: the page is still open and usable.
        browserOpen = reopen;
      }
      if (_current(epoch) && !results) _set(choiceError!);
    } finally {
      await refreshSignIn();
      _working = false;
      if (!_disposed) notifyListeners();
    }
    if (changed && reopen && !results && _current(epoch)) await open();
  }

  void _set(String value) {
    if (!_disposed) {
      phase = value;
      arrivals.accept(view, phase: value);
      notifyListeners();
    }
  }

  bool _current(int epoch) => !_disposed && epoch == _epoch;
  Future<void> clearData() async {
    if (busy || !canAct) return;
    _working = true;
    final epoch = ++_epoch;
    browserOpen = false;
    view = const {};
    _set('clearing');
    try {
      await browser.clearData();
      if (_current(epoch)) _set('cleared');
    } on Object catch (error) {
      if (_current(epoch)) {
        final code = error is HangarReaderFailure ? error.code : 'clear_failed';
        _set(
          ['clear_busy', 'clear_unsafe'].contains(code) ? code : 'clear_failed',
        );
      }
    } finally {
      await refreshSignIn();
      _working = false;
      if (!_disposed) notifyListeners();
    }
  }

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
      // After closing: that close may itself have failed to clear.
      await refreshSignIn();
      if (!_current(epoch)) return;
      final profileKey = await preview.prepare();
      if (!_current(epoch)) return;
      // A page left a moment ago may still be clearing its sign-in.
      final clearing = Stopwatch()..start();
      while (true) {
        try {
          await browser.open(profileKey: profileKey);
          break;
        } on HangarReaderFailure catch (error) {
          if (error.code != 'clear_busy' || clearing.elapsed >= pageTimeout) {
            rethrow;
          }
        }
        await Future<void>.delayed(pollInterval);
        if (!_current(epoch)) return;
      }
      if (!_current(epoch)) {
        await browser.close();
        return;
      }
      // Native opens only once no clear is running, so the start-up clear,
      // which may have run while opening waited, has reported by now.
      await refreshSignIn();
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
      await refreshSignIn();
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
      // Not remembering: a finished read, successful or not, ends the RSI
      // sign-in. Closing clears it natively.
      if (_current(epoch) &&
          browserOpen &&
          remember != true &&
          !_inPageSteps.contains(phase)) {
        browserOpen = false;
        try {
          await browser.close();
        } on Object {
          // Reported through the native clear status below.
        }
        await refreshSignIn();
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
    await refreshSignIn();
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
