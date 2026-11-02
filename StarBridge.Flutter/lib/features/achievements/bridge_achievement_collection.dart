import '../../platform/bridge/bridge_client_session.dart';
import 'achievement_collection_port.dart';
import 'achievement_catalog.dart';
import 'scm_achievement_wire.dart';
import '../onboarding/connection_mode_port.dart';
import '../account/account_models.dart';

final class BridgeAchievementCollection
    implements
        AchievementCollectionPort,
        AchievementCollectionInvalidations,
        AchievementCollectionChanges {
  const BridgeAchievementCollection(
    this.session, {
    this.mode,
    this.scm = false,
    this.retainedReadId,
    this.displayHandoff,
  });
  final bool scm;
  String get _command => scm ? 'scmAchievements.read' : 'achievements.read';
  final BridgeClientSession session;
  final ConnectionModeControl? mode;
  final String? Function()? retainedReadId;
  final AccountDisplayHandoff? Function()? displayHandoff;

  @override
  Stream<void> get invalidations => session.events
      .where(
        (event) =>
            event.name == 'account.changed' &&
            displayHandoff?.call()?.generation != event.sessionGeneration,
      )
      .map((_) {});

  @override
  Future<AchievementCollection> read({required int generation}) async {
    try {
      return await _read(generation: generation);
    } on BridgeClientException catch (error) {
      final transient =
          error is BridgeDisconnectedException ||
          error.code == 'bridge.timeout' ||
          const [
                'achievements.unavailable',
                'scmAchievements.unavailable',
                'scmAchievements.snapshot_changed',
              ].contains(error.code) &&
              error.retryable;
      if (!transient) rethrow;
      return AchievementCollection(
        generation: generation,
        status: AchievementCollectionStatus.unavailable,
        transientFailure: true,
      );
    }
  }

  @override
  Stream<void> get changes => session.events
      .where(
        (event) =>
            event.name ==
                (scm ? 'scmAchievements.changed' : 'achievements.changed') ||
            event.name == 'bootstrap.invalidated',
      )
      .map((_) {});

  Future<AchievementCollection> _read({required int generation}) async {
    AchievementCollection unavailable() => AchievementCollection(
      generation: generation,
      status: AchievementCollectionStatus.unavailable,
    );
    final control = mode;
    final readId = retainedReadId?.call();
    if (readId != null &&
        (control == null || !control.failed && control.allowsOnlineTraffic)) {
      if (generation != session.activeGeneration) return unavailable();
      final response = await session.request(
        'account.offlineData.read',
        payload: {
          'schemaVersion': 1,
          'readId': readId,
          'kind': scm ? 'scmAchievements' : 'achievements',
        },
      );
      if (retainedReadId?.call() != readId ||
          control != null && (control.failed || !control.allowsOnlineTraffic) ||
          response.accountContext != null ||
          response.sessionGeneration != generation ||
          session.activeGeneration != generation ||
          response.payload['schemaVersion'] != 1) {
        return unavailable();
      }
      if (scm) {
        return readScmAchievementPages(
          response.payload,
          (offset, snapshotId) async {
            final page = await session.request(
              'account.offlineData.read',
              payload: {
                'schemaVersion': 1,
                'readId': readId,
                'kind': 'scmAchievements',
                'offset': offset,
                'snapshotId': snapshotId,
              },
            );
            if (retainedReadId?.call() != readId ||
                control != null &&
                    (control.failed || !control.allowsOnlineTraffic) ||
                page.accountContext != null ||
                page.sessionGeneration != generation ||
                session.activeGeneration != generation) {
              throw const FormatException('SCM retained owner changed');
            }
            return page.payload;
          },
          generation: generation,
          cached: true,
        );
      }
      final rawAt = response.payload['cachedAtUtc'];
      final at = rawAt is String ? DateTime.tryParse(rawAt) : null;
      final collection = response.payload['collection'];
      if (at == null ||
          !at.isUtc ||
          !at.isAfter(DateTime.fromMillisecondsSinceEpoch(0, isUtc: true)) ||
          at.isAfter(DateTime.now().toUtc().add(const Duration(minutes: 5))) ||
          collection is! Map<String, Object?> ||
          collection['schemaVersion'] != 1) {
        return unavailable();
      }
      return parseCollection(collection, generation, cachedAtUtc: at);
    }
    if (control != null && !control.allowsOnlineTraffic) {
      final snapshot = control.snapshot;
      if (control.failed ||
          !snapshot.isOffline ||
          snapshot.offlineAccount == null ||
          snapshot.revision == null ||
          generation != session.activeGeneration) {
        return unavailable();
      }
      final response = await session.request(
        scm
            ? 'onboarding.mode.scmAchievements'
            : 'onboarding.mode.achievements',
        payload: {'schemaVersion': 1, 'revision': snapshot.revision},
      );
      final now = control.snapshot;
      if (control.failed ||
          !now.isOffline ||
          now.scope != snapshot.scope ||
          now.revision != snapshot.revision ||
          now.offlineAccount?.cachedAtUtc !=
              snapshot.offlineAccount!.cachedAtUtc ||
          response.accountContext != null ||
          response.sessionGeneration != generation ||
          session.activeGeneration != generation ||
          response.payload['schemaVersion'] != 1) {
        return unavailable();
      }
      if (scm) {
        return readScmAchievementPages(
          response.payload,
          (offset, snapshotId) async {
            final page = await session.request(
              'onboarding.mode.scmAchievements',
              payload: {
                'schemaVersion': 1,
                'revision': snapshot.revision,
                'offset': offset,
                'snapshotId': snapshotId,
              },
            );
            final current = control.snapshot;
            if (control.failed ||
                !current.isOffline ||
                current.scope != snapshot.scope ||
                current.revision != snapshot.revision ||
                current.offlineAccount?.cachedAtUtc !=
                    snapshot.offlineAccount!.cachedAtUtc ||
                page.accountContext != null ||
                page.sessionGeneration != generation ||
                session.activeGeneration != generation) {
              throw const FormatException('SCM offline owner changed');
            }
            return page.payload;
          },
          generation: generation,
          cached: true,
        );
      }
      final rawAt = response.payload['cachedAtUtc'];
      final at = rawAt is String ? DateTime.tryParse(rawAt) : null;
      final collection = response.payload['collection'];
      if (at == null ||
          !at.isUtc ||
          !at.isAfter(DateTime.fromMillisecondsSinceEpoch(0, isUtc: true)) ||
          at.isAfter(DateTime.now().toUtc().add(const Duration(minutes: 5))) ||
          collection is! Map<String, Object?> ||
          collection['schemaVersion'] != 1) {
        return unavailable();
      }
      return parseCollection(collection, generation, cachedAtUtc: at);
    }
    if (!session.hostCapabilities.contains(_command) ||
        generation != session.activeGeneration) {
      return unavailable();
    }
    final expected = displayHandoff?.call();
    final account = await session.request(
      'account.getCurrent',
      payload: const {'schemaVersion': 1},
    );
    if (account.payload['schemaVersion'] != 1 ||
        account.payload['state'] != 'signedIn' ||
        account.accountContext == null ||
        account.sessionGeneration != generation ||
        session.activeGeneration != generation) {
      return unavailable();
    }
    final context = account.accountContext!;
    if (displayHandoff?.call() != expected ||
        expected != null &&
            (expected.generation != generation ||
                !expected.matchesRoute(
                  AccountRoute(
                    environment: context.environment,
                    authority: context.authority,
                    subject: context.subject,
                  ),
                ))) {
      return unavailable();
    }
    final response = await session.request(
      _command,
      accountContext: account.accountContext,
      payload: const {'schemaVersion': 1},
    );
    final owner = account.accountContext!, returned = response.accountContext;
    if (response.sessionGeneration != generation ||
        displayHandoff?.call() != expected ||
        session.activeGeneration != generation ||
        returned == null ||
        returned.environment != owner.environment ||
        returned.authority != owner.authority ||
        returned.subject != owner.subject ||
        response.payload['schemaVersion'] != 1) {
      return unavailable();
    }
    if (scm) {
      return readScmAchievementPages(
        response.payload,
        (offset, snapshotId) async {
          final page = await session.request(
            _command,
            accountContext: owner,
            payload: {
              'schemaVersion': 1,
              'offset': offset,
              'snapshotId': snapshotId,
            },
          );
          final returned = page.accountContext;
          if (page.sessionGeneration != generation ||
              displayHandoff?.call() != expected ||
              session.activeGeneration != generation ||
              returned == null ||
              returned.environment != owner.environment ||
              returned.authority != owner.authority ||
              returned.subject != owner.subject ||
              control != null && !control.allowsOnlineTraffic) {
            throw const FormatException('SCM online owner changed');
          }
          return page.payload;
        },
        generation: generation,
        cached: false,
      );
    }
    return parseCollection(response.payload, generation);
  }

  static AchievementCollection parseCollection(
    Map<String, Object?> payload,
    int generation, {
    DateTime? cachedAtUtc,
  }) {
    AchievementCollection unavailable() => AchievementCollection(
      generation: generation,
      status: AchievementCollectionStatus.unavailable,
    );
    final raw = payload['earnedAt'];
    if (raw is! Map || raw.length > 256) return unavailable();
    final earned = <String, DateTime>{};
    for (final entry in raw.entries) {
      if (entry.key is! String ||
          !RegExp(r'^[a-zA-Z0-9-]{1,64}$').hasMatch(entry.key as String) ||
          entry.value is! String) {
        return unavailable();
      }
      final at = DateTime.tryParse(entry.value as String);
      if (at == null ||
          !at.isUtc ||
          !at.isAfter(DateTime.fromMillisecondsSinceEpoch(0, isUtc: true)) ||
          at.isAfter(DateTime.now().toUtc().add(const Duration(minutes: 5)))) {
        return unavailable();
      }
      earned[entry.key as String] = at;
    }
    final rawProgress = payload['progress'];
    Map<String, int>? progress;
    if (rawProgress != null) {
      if (rawProgress is! Map || rawProgress.length > 4) return unavailable();
      progress = <String, int>{};
      for (final entry in rawProgress.entries) {
        if (!const [
              'hangar-home',
              'hangar-collection',
              'hangar-paths',
              'journey-stanton',
            ].contains(entry.key) ||
            entry.value is! int ||
            entry.value < 0 ||
            entry.value >
                switch (entry.key) {
                  'hangar-paths' => 6,
                  'journey-stanton' => 4,
                  _ => 10000,
                }) {
          return unavailable();
        }
        progress[entry.key as String] = entry.value as int;
      }
    }
    for (final definition in achievementCatalog.where((d) => d.isSeries)) {
      var gap = false;
      for (var rank = 1; rank <= 5; rank++) {
        final obtained = earned.containsKey('${definition.id}-$rank');
        if (!obtained) {
          gap = true;
          continue;
        }
        if (gap ||
            progress != null &&
                progress[definition.id] != null &&
                progress[definition.id]! < definition.thresholds[rank - 1]) {
          return unavailable();
        }
      }
    }
    return AchievementCollection(
      generation: generation,
      status: AchievementCollectionStatus.ready,
      earnedAt: earned,
      progress: progress,
      cachedAtUtc: cachedAtUtc,
      synchronizedAtUtc: _syncTime(payload['synchronizedAtUtc']),
      refreshFailed: payload['refreshFailed'] == true,
    );
  }

  static DateTime? _syncTime(Object? value) {
    final at = value is String ? DateTime.tryParse(value) : null;
    return at != null &&
            at.isUtc &&
            at.isAfter(DateTime.fromMillisecondsSinceEpoch(0, isUtc: true)) &&
            !at.isAfter(DateTime.now().toUtc().add(const Duration(minutes: 5)))
        ? at
        : null;
  }
}
