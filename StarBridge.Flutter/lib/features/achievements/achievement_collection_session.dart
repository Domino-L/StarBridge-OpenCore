import 'dart:async';

import 'package:flutter/foundation.dart';

import '../account/account_models.dart';
import '../onboarding/connection_mode_port.dart';
import 'achievement_collection_controller.dart';
import 'achievement_collection_port.dart';
import 'achievement_read_scope.dart';

/// Owns one bounded collection and numeric viewport state for a feature session.
/// Constructing the feature starts no reads. Pages borrow, and never own, it.
final class AchievementCollectionSession {
  AchievementCollectionSession({
    required this.account,
    required this.port,
    this.mode,
    this.clock,
    this.permanentMilestones = true,
    this.freshFor = const Duration(minutes: 5),
  }) {
    _scope = achievementReadScope(account.value, mode);
    account.addListener(_scopeChanged);
    mode?.addListener(_scopeChanged);
    if (port case AchievementCollectionInvalidations source) {
      _invalidations = source.invalidations.listen((_) => _resetViewport());
    }
  }
  final ValueListenable<AccountProjection> account;
  final AchievementCollectionPort port;
  final ConnectionModeControl? mode;
  final DateTime Function()? clock;
  final Duration freshFor;
  final bool permanentMilestones;
  AchievementCollectionController? _collection;
  StreamSubscription<void>? _invalidations;
  late Object _scope;
  bool _disposed = false;
  double _scrollOffset = 0;
  int _viewEpoch = 0;
  double get scrollOffset => _scrollOffset;
  int get viewEpoch => _viewEpoch;

  AchievementCollectionController get collection {
    if (_disposed) throw StateError('Achievement session is disposed');
    return _collection ??= AchievementCollectionController(
      account: account,
      port: port,
      mode: mode,
      lazy: true,
      permanentMilestones: permanentMilestones,
      clock: clock,
      freshFor: freshFor,
    );
  }

  Future<void> activate() =>
      _disposed ? Future.value() : collection.ensureLoaded();

  void rememberScroll(double offset, {required int expectedEpoch}) {
    if (!_disposed &&
        expectedEpoch == _viewEpoch &&
        offset.isFinite &&
        offset >= 0) {
      _scrollOffset = offset;
    }
  }

  void _scopeChanged() {
    final next = achievementReadScope(account.value, mode);
    if (next == _scope) return;
    _scope = next;
    if (_collection?.preservesScopePresentation == true) return;
    _resetViewport();
  }

  void _resetViewport() {
    if (_disposed) return;
    _viewEpoch++;
    _scrollOffset = 0;
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    account.removeListener(_scopeChanged);
    mode?.removeListener(_scopeChanged);
    unawaited(_invalidations?.cancel());
    _collection?.dispose();
  }
}
