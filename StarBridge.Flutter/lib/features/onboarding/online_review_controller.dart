import 'dart:async';

import 'package:flutter/foundation.dart';

import 'online_review_port.dart';
import 'online_installation_port.dart';

@immutable
final class OnlineReviewView {
  const OnlineReviewView({
    this.snapshot = const OnlineReviewSnapshot(),
    this.busy = false,
    this.error = false,
    this.action,
  });
  final OnlineReviewSnapshot snapshot;
  final bool busy, error;
  final OnlineReviewAction? action;
  bool get canConfirm => !busy && !error && snapshot.canConfirm;
}

// UI owns only waiting/drafts. All identity and mode decisions stay on Host.
final class OnlineReviewController extends ValueNotifier<OnlineReviewView> {
  OnlineReviewController(this.port, {this.installation, this.onInstalled})
    : super(const OnlineReviewView()) {
    _events = port.invalidations.listen((_) {
      if (_disposed) return;
      _epoch++;
      _refreshPending = true;
      value = OnlineReviewView(
        snapshot: OnlineReviewSnapshot(
          retainsSession: value.snapshot.retainsSession,
        ),
        busy: _active != null,
        action: value.action,
      );
      if (_active == null) unawaited(refresh());
    });
  }
  final OnlineReviewPort port;
  final OnlineInstallationPort? installation;
  final Future<void> Function()? onInstalled;
  int? _installationRevision;
  late final StreamSubscription<void> _events;
  int _epoch = 0, _work = 0;
  int? _active, _cancelRevision;
  bool _disposed = false, _refreshPending = false;
  bool get canCancelLogin =>
      !_disposed &&
      value.busy &&
      (value.action == OnlineReviewAction.login ||
          value.action == OnlineReviewAction.resume ||
          value.action == OnlineReviewAction.reauthorize) &&
      _cancelRevision != null;
  Future<void> refresh() async {
    if (_installationRevision != null) {
      await _installAccount(observe: true);
    } else {
      await _request(port.read);
      await _continueConfirmedAccount();
    }
  }

  Future<void> _continueConfirmedAccount() async {
    if (!_disposed &&
        !value.busy &&
        !value.error &&
        _installationRevision == null &&
        value.snapshot.retainsSession &&
        installation?.supported == true &&
        (value.snapshot.state == OnlineReviewState.accountConfirmedForHandoff ||
            value.snapshot.identityConfirmed)) {
      await _installAccount();
    }
  }

  Future<void> signIn() async {
    if (value.snapshot.retainsSession &&
        (value.snapshot.state == OnlineReviewState.accountConfirmedForHandoff ||
            value.snapshot.identityConfirmed)) {
      await _continueConfirmedAccount();
    }
    if (value.snapshot.canBegin) await execute(OnlineReviewAction.begin);
    if (!_disposed && !value.error && value.snapshot.canLogin) {
      await execute(OnlineReviewAction.login);
    } else if (!_disposed && !value.error && value.snapshot.canResume) {
      await execute(OnlineReviewAction.resume);
    }
    if (!_disposed &&
        !value.error &&
        value.snapshot.retainsSession &&
        value.snapshot.canConfirm &&
        installation?.supported == true) {
      await execute(OnlineReviewAction.confirm);
    }
  }

  Future<void> _installAccount({bool observe = false}) async {
    final target = installation;
    final revision = _installationRevision ?? value.snapshot.revision;
    if (target == null || !target.supported || revision == null) {
      await _request(port.read);
      return;
    }
    _installationRevision = revision;
    await _request(() async {
      final result = observe
          ? await target.read(revision)
          : await target.install(revision);
      if (result.phase == OnlineInstallationPhase.idle ||
          (result.phase == OnlineInstallationPhase.completed &&
              result.modeState != 'online')) {
        _installationRevision = null;
        return port.read();
      }
      if (result.phase != OnlineInstallationPhase.completed) {
        throw StateError('Account restoration has not completed.');
      }
      await onInstalled?.call();
      _installationRevision = null;
      return port.read();
    });
  }

  Future<void> execute(OnlineReviewAction action) async {
    if (_disposed) return;
    if (action == OnlineReviewAction.cancel && canCancelLogin) {
      final revision = _cancelRevision!;
      await _request(
        () => port.execute(action, revision),
        action: action,
        supersede: true,
      );
      return;
    }
    final snapshot = value.snapshot;
    if (value.busy ||
        value.error ||
        snapshot.revision == null ||
        !(switch (action) {
          OnlineReviewAction.begin => snapshot.canBegin,
          OnlineReviewAction.login => snapshot.canLogin,
          OnlineReviewAction.resume => snapshot.canResume,
          OnlineReviewAction.reauthorize => snapshot.canReauthorize,
          OnlineReviewAction.review => snapshot.canReview,
          OnlineReviewAction.confirm => snapshot.canConfirm,
          OnlineReviewAction.cancel => snapshot.canCancel,
        })) {
      return;
    }
    await _request(
      () => port.execute(
        action,
        snapshot.revision!,
        confirmationKey: snapshot.confirmationKey,
      ),
      action: action,
    );
    await _continueConfirmedAccount();
  }

  Future<void> _request(
    Future<OnlineReviewSnapshot> Function() request, {
    OnlineReviewAction? action,
    bool supersede = false,
  }) async {
    if (_disposed || _active != null && !supersede) return;
    final work = ++_work, epoch = ++_epoch;
    _active = work;
    if (action == OnlineReviewAction.login ||
        action == OnlineReviewAction.resume ||
        action == OnlineReviewAction.reauthorize) {
      _cancelRevision = value.snapshot.revision;
    }
    value = OnlineReviewView(
      snapshot: value.snapshot,
      busy: true,
      action: action,
    );
    try {
      final result = await request();
      if (!_disposed && work == _active && epoch == _epoch) {
        value = OnlineReviewView(snapshot: result);
      }
    } on Object {
      if (!_disposed && work == _active && epoch == _epoch) {
        value = OnlineReviewView(
          snapshot: OnlineReviewSnapshot(
            retainsSession: value.snapshot.retainsSession,
          ),
          error: true,
        );
      }
    } finally {
      if (!_disposed && work == _active) {
        _active = null;
        _cancelRevision = null;
        if (value.busy) value = const OnlineReviewView();
        if (_refreshPending) {
          _refreshPending = false;
          unawaited(refresh());
        }
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _epoch++;
    unawaited(_events.cancel());
    super.dispose();
  }
}
