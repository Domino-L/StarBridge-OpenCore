import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../features/game_log/game_log_controller.dart';
import '../../features/account/account_models.dart';
import '../../features/account/handle_mismatch_port.dart';

typedef HandleMismatchKey = (int, String, String);

@immutable
final class HandleMismatchNotice {
  const HandleMismatchNotice({
    required this.generation,
    required this.expectedHandle,
    required this.detectedHandle,
    required this.binding,
  });
  final int generation;
  final String expectedHandle;
  final String? detectedHandle;
  final AccountScmBindingState binding;
  HandleMismatchKey get key => (
    generation,
    expectedHandle.toLowerCase(),
    detectedHandle?.toLowerCase() ?? '',
  );
  bool get hasPair => detectedHandle != null;
}

/// Keeps account-scoped mismatch evidence across navigation and transient reads.
/// Closing a prompt never changes this state or clears the persistent notice.
final class HandleMismatchModule extends ChangeNotifier {
  HandleMismatchModule({
    required this.account,
    required this.gameLog,
    required this.port,
    required this.refresh,
    this.activeGeneration,
    Stream<void>? invalidations,
  }) {
    account.addListener(_changed);
    gameLog?.addListener(_changed);
    _invalidations = invalidations?.listen((_) => _changed());
    _changed();
  }
  final ValueListenable<AccountProjection> account;
  final ValueListenable<GameLogView>? gameLog;
  final HandleMismatchPort? port;
  final Future<void> Function() refresh;
  final int Function()? activeGeneration;
  StreamSubscription<void>? _invalidations;
  int get currentGeneration =>
      activeGeneration?.call() ?? account.value.generation;
  HandleMismatchNotice? _notice;
  HandleMismatchNotice? get notice =>
      _notice?.generation == currentGeneration ? _notice : null;
  bool busy = false, failed = false;
  HandleCheckState? checkState;
  (HandleMismatchKey, String)? _confirmation;
  bool get canConfirm =>
      !busy &&
      !failed &&
      checkState == HandleCheckState.ready &&
      port is LegacyHandleChangePort &&
      _confirmation?.$1 == notice?.key &&
      _confirmation != null &&
      account.value.sessionState == AccountSessionState.legacySignedIn;
  bool _disposed = false;
  int _epoch = 0;

  bool isCurrent(HandleMismatchKey key) =>
      !_disposed && currentGeneration == key.$1 && notice?.key == key;

  static String? _handle(String? value) =>
      value == null || value.trim().isEmpty ? null : value.trim();

  void _changed() {
    if (_disposed) return;
    final current = account.value;
    final signedIn =
        current.sessionState == AccountSessionState.signedIn ||
        current.sessionState == AccountSessionState.legacySignedIn;
    final old = _notice;
    if (current.generation != currentGeneration) {
      _notice = null;
      _epoch++;
      busy = false;
      failed = false;
      checkState = null;
      notifyListeners();
      return;
    }
    // Temporary credential/network failures do not undo confirmed evidence.
    // An explicit sign-out or a new owner generation does.
    if (current.sessionState == AccountSessionState.signedOut ||
        (old != null && old.generation != current.generation)) {
      _notice = null;
      busy = false;
      failed = false;
      checkState = null;
      _epoch++;
    }
    if (signedIn) {
      final observation = gameLog?.value;
      final observedMismatch = observation?.match == 'mismatch';
      final policyMismatch =
          current.identity.state == AccountIdentityState.mismatch;
      final expected =
          _handle(current.identity.authoritativeHandle) ??
          (observedMismatch ? _handle(observation?.expectedHandle) : null);
      final detected =
          _handle(current.identity.detectedHandle) ??
          (observedMismatch ? _handle(observation?.handle) : null);
      if ((policyMismatch || observedMismatch) &&
          expected != null &&
          (detected == null ||
              expected.toLowerCase() != detected.toLowerCase())) {
        final next = HandleMismatchNotice(
          generation: current.generation,
          expectedHandle: expected,
          detectedHandle:
              detected ??
              (_notice?.expectedHandle.toLowerCase() == expected.toLowerCase()
                  ? _notice?.detectedHandle
                  : null),
          binding: current.identity.scmBindingState,
        );
        if (_notice?.key != next.key) {
          _epoch++;
          busy = false;
          failed = false;
          checkState = null;
        }
        _notice = next;
      } else if (!policyMismatch &&
          !observedMismatch &&
          current.identity.state == AccountIdentityState.match) {
        _notice = null;
        _epoch++;
        busy = false;
        failed = false;
        checkState = null;
      }
    }
    if (old?.key != _notice?.key || old?.binding != _notice?.binding) {
      notifyListeners();
    }
  }

  Future<void> recheck() async {
    final selected = notice;
    if (_disposed || selected == null || busy) return;
    final epoch = _epoch;
    busy = true;
    failed = false;
    _confirmation = null;
    notifyListeners();
    try {
      final source = port;
      if (source == null) {
        throw const FormatException('Identity check unavailable.');
      }
      final result = await source.check(selected.generation);
      if (_disposed || epoch != _epoch || !isCurrent(selected.key)) return;
      if ((result.state == HandleCheckState.ready ||
              result.state == HandleCheckState.bound ||
              result.state == HandleCheckState.unknown) &&
          (result.expectedHandle?.toLowerCase() !=
                  selected.expectedHandle.toLowerCase() ||
              (selected.detectedHandle != null &&
                  result.detectedHandle?.toLowerCase() !=
                      selected.detectedHandle!.toLowerCase()))) {
        throw const FormatException('Identity observation changed.');
      }
      checkState = result.state;
      if (result.state == HandleCheckState.ready &&
          result.confirmationId != null) {
        _confirmation = (selected.key, result.confirmationId!);
      }
      // A read result never renames the account. Refresh the existing owners
      // before clearing a mismatch; do not treat a "consistent" string alone as proof.
      await refresh();
    } catch (_) {
      if (!_disposed && epoch == _epoch && isCurrent(selected.key)) {
        failed = true;
      }
    } finally {
      if (!_disposed && epoch == _epoch && isCurrent(selected.key)) {
        busy = false;
        notifyListeners();
      }
    }
  }

  Future<void> confirm() async {
    final ticket = _confirmation;
    final writer = port is LegacyHandleChangePort
        ? port as LegacyHandleChangePort
        : null;
    if (!canConfirm || ticket == null || writer == null) {
      return;
    }
    _confirmation = null; // One user gesture, at most one submission.
    final epoch = _epoch;
    busy = true;
    failed = false;
    checkState = HandleCheckState.outcomeUnknown;
    notifyListeners();
    try {
      await writer.confirm(ticket.$1.$1, ticket.$2);
      if (_disposed || epoch != _epoch || !isCurrent(ticket.$1)) return;
      await refresh();
    } catch (_) {
      if (!_disposed && epoch == _epoch && isCurrent(ticket.$1)) failed = true;
    } finally {
      if (!_disposed && epoch == _epoch && isCurrent(ticket.$1)) {
        busy = false;
        notifyListeners();
      }
    }
  }

  void dismissConfirmation(HandleMismatchKey key) {
    final ticket = _confirmation;
    if (ticket == null || ticket.$1 != key) return;
    _confirmation = null;
    if (checkState == HandleCheckState.ready) checkState = null;
    final writer = port is LegacyHandleChangePort
        ? port as LegacyHandleChangePort
        : null;
    if (writer != null) {
      unawaited(writer.cancel(key.$1, ticket.$2).catchError((Object _) {}));
    }
    if (!_disposed) notifyListeners();
  }

  Future<HandleNotificationReceipt?> notifyBackground(
    HandleMismatchKey key,
  ) async {
    if (!isCurrent(key)) return null;
    return await port?.notifyBackground(key.$1);
  }

  @override
  void dispose() {
    _disposed = true;
    _epoch++;
    account.removeListener(_changed);
    gameLog?.removeListener(_changed);
    unawaited(_invalidations?.cancel());
    super.dispose();
  }
}
