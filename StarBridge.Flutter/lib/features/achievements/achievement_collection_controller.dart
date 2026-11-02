import 'dart:async';

import 'package:flutter/foundation.dart';

import '../account/account_models.dart';
import '../onboarding/connection_mode_port.dart';
import 'achievement_collection_port.dart';
import 'achievement_read_scope.dart';

final class AchievementCollectionController
    extends ValueNotifier<AchievementCollection> {
  AchievementCollectionController({
    required this.account,
    required this.port,
    this.mode,
    this.lazy = false,
    this.permanentMilestones = true,
    DateTime Function()? clock,
    this.freshFor = const Duration(minutes: 5),
  }) : _clock = clock ?? DateTime.now,
       super(
         AchievementCollection(
           generation: account.value.generation,
           status: AchievementCollectionStatus.loading,
         ),
       ) {
    account.addListener(_onScopeChanged);
    mode?.addListener(_onScopeChanged);
    if (port case AchievementCollectionInvalidations source) {
      _invalidations = source.invalidations.listen((_) => _invalidate());
    }
    if (port case AchievementCollectionChanges source) {
      _changes = source.changes.listen((_) => _contentChanged());
    }
    _onScopeChanged();
  }

  final ValueListenable<AccountProjection> account;
  final AchievementCollectionPort port;
  final ConnectionModeControl? mode;
  final bool lazy, permanentMilestones;
  final Duration freshFor;
  final DateTime Function() _clock;
  StreamSubscription<void>? _invalidations, _changes;
  Object? _scope, _dataScope, _pendingScope, _baseScope;
  ({int generation, String id, Object mode})? _retainedDisplay;
  Future<void>? _pendingRead;
  DateTime? _readAt;
  bool get hasMaterializedHandoff => _canHandoff;
  bool get preservesScopePresentation =>
      _canHandoff ||
      account.value.isSignedIn &&
          value.isReady &&
          value.cachedAtUtc == null &&
          _dataScope != null &&
          (_baseScope == achievementReadBaseScope(account.value, mode) ||
              _followsProvenModeGeneration);
  int _readEpoch = 0;
  bool _disposed = false, _stale = true, _refreshQueued = false;

  bool get canRefresh {
    final current = account.value;
    final control = mode;
    final offline =
        control != null &&
        !control.failed &&
        control.snapshot.isOffline &&
        control.snapshot.offlineAccount != null;
    final retained =
        current.hasRetainedDisplayRead &&
        (control == null || !control.failed && control.allowsOnlineTraffic);
    final signedIn =
        current.isSignedIn ||
        current.sessionState == AccountSessionState.legacySignedIn;
    return !_disposed &&
        (offline ||
            retained ||
            signedIn && (control == null || control.allowsOnlineTraffic));
  }

  bool get needsRefresh =>
      !_disposed &&
      (_stale ||
          !value.isReady ||
          _readAt == null ||
          value.cachedAtUtc == null &&
              _clock().toUtc().difference(_readAt!) >= freshFor);

  Future<void> ensureLoaded() => _disposed
      ? Future.value()
      : _pendingRead ?? (needsRefresh ? refresh() : Future.value());

  void _onScopeChanged() {
    final next = achievementReadScope(account.value, mode);
    final base = achievementReadBaseScope(account.value, mode);
    final sameBase = base == _baseScope || _followsProvenModeGeneration;
    _baseScope = base;
    if (next == _scope) return;
    _scope = next;
    if (sameBase &&
        account.value.isSignedIn &&
        value.isReady &&
        value.cachedAtUtc == null &&
        _dataScope != null) {
      final reading = _pendingRead != null;
      ++_readEpoch;
      _pendingRead = null;
      _pendingScope = null;
      _dataScope = next;
      if (reading) {
        _stale = true;
        value = _retain(value, refreshing: true);
        if (!lazy || hasListeners) unawaited(refresh());
      }
      return;
    }
    if (_canHandoff) {
      ++_readEpoch;
      _pendingRead = null;
      _pendingScope = null;
      _dataScope = next;
      _stale = true;
      _refreshQueued = false;
      value = _retain(
        value,
        generation: account.value.generation,
        refreshing: true,
      );
      if (canRefresh && (!lazy || hasListeners)) unawaited(refresh());
      return;
    }
    _invalidate();
  }

  bool get _followsProvenModeGeneration {
    final current = account.value;
    final proof = current.hasDisplayHandoff ? current.displayHandoff : null;
    return proof != null &&
        current.isSignedIn &&
        current.generation == proof.generation &&
        mode?.snapshot.scope == proof.generation &&
        _baseScope ==
            achievementReadBaseScope(
              current,
              mode,
              modeScope: proof.sourceGeneration,
            );
  }

  bool get _canHandoff {
    final current = account.value, source = _retainedDisplay;
    final proof = current.hasDisplayHandoff ? current.displayHandoff : null;
    return proof != null &&
        source != null &&
        value.isReady &&
        value.cachedAtUtc != null &&
        source.id == proof.displayKey &&
        source.generation == proof.sourceGeneration &&
        (_reconcilingMode(proof, source.mode) ||
            (mode == null || !mode!.failed && mode!.allowsOnlineTraffic) &&
                (source.mode == achievementModeScope(mode) ||
                    (mode?.snapshot.scope == proof.generation &&
                        source.mode ==
                            achievementModeScope(
                              mode,
                              scope: proof.sourceGeneration,
                            ))));
  }

  bool _reconcilingMode(AccountDisplayHandoff proof, Object previousMode) {
    final control = mode;
    final continuity = control is ConnectionModeDisplayContinuitySource
        ? (control as ConnectionModeDisplayContinuitySource).displayContinuity
        : null;
    return control != null &&
        !control.failed &&
        control.snapshot.state == ConnectionModeState.unavailable &&
        continuity != null &&
        continuity.sourceGeneration == proof.sourceGeneration &&
        continuity.generation == proof.generation &&
        previousMode ==
            achievementModeScope(
              control,
              snapshot: ConnectionModeSnapshot(
                scope: continuity.sourceGeneration,
                revision: continuity.revision,
                state: ConnectionModeState.online,
              ),
            );
  }

  AchievementCollection _empty() => AchievementCollection(
    generation: account.value.generation,
    status: canRefresh
        ? AchievementCollectionStatus.loading
        : mode != null && !mode!.allowsOnlineTraffic
        ? AchievementCollectionStatus.unavailable
        : switch (account.value.sessionState) {
            AccountSessionState.loading => AchievementCollectionStatus.loading,
            AccountSessionState.signedOut ||
            AccountSessionState.reauthorizationRequired =>
              AchievementCollectionStatus.signedOut,
            _ => AchievementCollectionStatus.unavailable,
          },
  );

  void _invalidate() {
    if (_disposed) return;
    ++_readEpoch;
    _pendingRead = null;
    _pendingScope = null;
    _dataScope = null;
    _retainedDisplay = null;
    _readAt = null;
    _stale = true;
    _refreshQueued = false;
    value = _empty();
    if (!lazy || hasListeners) unawaited(refresh());
  }

  void _contentChanged() {
    if (_disposed) return;
    _stale = true;
    if (_pendingRead != null) {
      _refreshQueued = true;
    } else if (!lazy || hasListeners) {
      unawaited(refresh());
    }
  }

  Future<void> refresh() {
    if (_disposed) return Future.value();
    final scope = achievementReadScope(account.value, mode);
    if (_pendingRead != null && _pendingScope == scope) return _pendingRead!;
    final epoch = ++_readEpoch;
    if (!canRefresh) {
      if (_canHandoff) {
        value = _retain(
          value,
          generation: account.value.generation,
          refreshing: true,
        );
        return Future.value();
      }
      _dataScope = null;
      _readAt = null;
      value = _empty();
      return Future.value();
    }
    final previous = value.isReady && _dataScope == scope ? value : null;
    value = previous == null
        ? AchievementCollection(
            generation: account.value.generation,
            status: AchievementCollectionStatus.loading,
          )
        : _retain(previous, refreshing: true);
    final task = _read(scope, epoch, account.value.generation, previous);
    _pendingScope = scope;
    _pendingRead = task;
    unawaited(
      task.then((_) {
        if (_disposed || !identical(_pendingRead, task)) return;
        _pendingRead = null;
        _pendingScope = null;
        if (_refreshQueued) {
          _refreshQueued = false;
          _stale = true;
          if (!lazy || hasListeners) unawaited(refresh());
        }
      }),
    );
    return task;
  }

  Future<void> _read(
    Object scope,
    int epoch,
    int generation,
    AchievementCollection? previous,
  ) async {
    AchievementCollection result;
    try {
      result = await port.read(generation: generation);
    } on TimeoutException {
      result = AchievementCollection(
        generation: generation,
        status: AchievementCollectionStatus.unavailable,
        transientFailure: true,
      );
    } catch (_) {
      result = AchievementCollection(
        generation: generation,
        status: AchievementCollectionStatus.unavailable,
      );
    }
    if (_disposed ||
        epoch != _readEpoch ||
        achievementReadScope(account.value, mode) != scope) {
      return;
    }
    if (result.generation == generation && result.isReady) {
      final id = account.value.hasRetainedDisplayRead
          ? account.value.retainedReadId
          : null;
      _retainedDisplay =
          result.cachedAtUtc != null &&
              id != null &&
              (mode == null || !mode!.failed && mode!.allowsOnlineTraffic)
          ? (generation: generation, id: id, mode: achievementModeScope(mode))
          : null;
      _dataScope = scope;
      _readAt = _clock().toUtc();
      _stale = _refreshQueued;
      value = AchievementCollection(
        generation: generation,
        status: AchievementCollectionStatus.ready,
        // These are permanent server-confirmed milestones for this exact
        // account scope, not grants inferred from local game evidence.
        earnedAt: permanentMilestones
            ? {...result.earnedAt, ...?previous?.earnedAt}
            : result.earnedAt,
        catalog: result.catalog,
        ownedIds: result.ownedIds,
        progress: permanentMilestones
            ? _mergeProgress(previous?.progress, result.progress)
            : result.progress,
        cachedAtUtc: result.cachedAtUtc,
        synchronizedAtUtc:
            result.synchronizedAtUtc ?? result.cachedAtUtc ?? _readAt,
        refreshFailed: result.refreshFailed,
      );
    } else if (result.generation == generation &&
        result.status == AchievementCollectionStatus.unavailable &&
        previous != null &&
        (permanentMilestones || result.transientFailure)) {
      _stale = true;
      value = _retain(previous, failed: true);
    } else {
      _retainedDisplay = null;
      _dataScope = null;
      _readAt = null;
      _stale = true;
      value = AchievementCollection(
        generation: generation,
        status: AchievementCollectionStatus.unavailable,
      );
    }
  }

  static Map<String, num>? _mergeProgress(
    Map<String, num>? previous,
    Map<String, num>? next,
  ) {
    if (previous == null && next == null) return null;
    final merged = {...?previous};
    for (final entry in (next ?? const <String, int>{}).entries) {
      if (!merged.containsKey(entry.key) || entry.value > merged[entry.key]!) {
        merged[entry.key] = entry.value;
      }
    }
    return merged;
  }

  AchievementCollection _retain(
    AchievementCollection previous, {
    bool refreshing = false,
    bool failed = false,
    int? generation,
  }) => AchievementCollection(
    generation: generation ?? previous.generation,
    status: AchievementCollectionStatus.ready,
    earnedAt: previous.earnedAt,
    catalog: previous.catalog,
    ownedIds: previous.ownedIds,
    unknownIds: previous.unknownIds,
    progress: previous.progress,
    cachedAtUtc: previous.cachedAtUtc,
    synchronizedAtUtc: previous.synchronizedAtUtc,
    isRefreshing: refreshing,
    refreshFailed: failed,
  );

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    ++_readEpoch;
    account.removeListener(_onScopeChanged);
    mode?.removeListener(_onScopeChanged);
    unawaited(_invalidations?.cancel());
    unawaited(_changes?.cancel());
    super.dispose();
  }
}
