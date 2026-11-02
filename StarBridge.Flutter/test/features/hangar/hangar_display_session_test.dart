import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/account/account_models.dart';
import 'package:starbridge_flutter/features/hangar/hangar_display_session.dart';
import 'package:starbridge_flutter/features/hangar/local_hangar_port.dart';
import 'package:starbridge_flutter/features/hangar/local_hangar_read_scope.dart';
import 'package:starbridge_flutter/features/hangar/local_hangar_images.dart';
import 'package:starbridge_flutter/features/communities/community_logo_port.dart';

const _id = '0123456789abcdef0123456789abcdef';
const _route = AccountRoute(
  environment: 'integration',
  authority: 'synthetic',
  subject: 'owner',
);
const _proof = AccountDisplayHandoff(
  displayKey: _id,
  sourceGeneration: 0,
  route: _route,
);
const _cached = LocalHangarSnapshot(
  revision: 7,
  ships: [LocalHangarShip(id: 'ship', title: 'Cached ship')],
);
const _fresh = LocalHangarSnapshot(
  revision: 1,
  ships: [LocalHangarShip(id: 'ship', title: 'Fresh ship')],
);
AccountProjection projection({
  int generation = 0,
  String? id,
  bool signedIn = false,
  AccountDisplayHandoff? proof,
}) => AccountProjection(
  generation: generation,
  sessionState: signedIn
      ? AccountSessionState.signedIn
      : AccountSessionState.loading,
  operation: signedIn ? AccountOperation.none : AccountOperation.refreshing,
  profileFreshness: AccountProfileFreshness.cached,
  cachedAt: DateTime.utc(2026, 10, 1),
  retainedReadId: id,
  preparingDisplay: true,
  displayHandoff: proof,
  identity: const AccountIdentityProjection.unavailable(),
  compatibility: const AccountCompatibilityProjection.unavailable(),
  localeOptions: const [],
  timeZoneOptions: const [],
);

class _Port
    implements
        LocalHangarPort,
        LocalHangarReadScopeSource,
        LocalHangarFavoritesPort,
        LocalHangarPersonalDataPort,
        LocalHangarImageProvider {
  final reads = <Completer<LocalHangarSnapshot>>[];
  int writes = 0;
  final image = _Image();
  @override
  LocalHangarImagePort? imageFor(String shipId, int revision) => image;
  @override
  LocalHangarReadScope? readScope;
  @override
  bool get favoritesAvailable => true;
  @override
  bool get personalDataAvailable => true;
  @override
  Future<LocalHangarSnapshot> readPersonalDataReceipt() async => _fresh;
  @override
  Future<LocalHangarSnapshot> savePersonalData(
    String shipId,
    String? nickname,
    String? notes,
    int expectedRevision, {
    required String operationId,
  }) async => LocalHangarSnapshot(
    revision: expectedRevision + 1,
    operationId: operationId,
    ships: [
      LocalHangarShip(
        id: shipId,
        title: 'Fresh ship',
        nickname: nickname,
        notes: notes,
      ),
    ],
  );
  @override
  Future<LocalHangarSnapshot> read() {
    final pending = Completer<LocalHangarSnapshot>();
    reads.add(pending);
    return pending.future;
  }

  @override
  Future<LocalHangarSnapshot> save(
    String operationId,
    int expectedRevision, {
    bool confirmEmpty = false,
  }) async {
    ++writes;
    return _fresh;
  }

  @override
  Future<LocalHangarSnapshot> setFavorite(
    String shipId,
    bool favorite,
    int expectedRevision,
  ) async {
    ++writes;
    return _fresh;
  }
}

class _Image implements LocalHangarImagePort {
  int reads = 0;
  Completer<String?>? pending;
  @override
  bool get canPickLogo => true;
  @override
  Future<String?> readImage() async {
    ++reads;
    return pending?.future;
  }

  @override
  Future<void> saveImage() async {}
  @override
  Future<void> restoreImage() async {}
  @override
  Future<void> clearLogo() async {}
  @override
  Future<CommunityLogoSource?> pickLogo() async => null;
  @override
  Future<String> cropLogo(
    String sourceRef,
    double x,
    double y,
    double size,
  ) async => 'fixture';
}

class _Harness {
  final account = ValueNotifier(projection(id: _id));
  final cached = _Port(), fresh = _Port();
  late final display = HangarDisplaySession(
    account: account,
    retainedFactory: (_) => cached,
    localFactory: () => fresh,
  );
  Future<void> load() async {
    final pending = display.read();
    cached.reads.single.complete(_cached);
    await pending;
    display.view
      ..query = 'ship'
      ..scrollOffset = 300
      ..grid = false;
  }

  void handoff() {
    account.value = projection(proof: _proof);
    account.value = projection(generation: 1, proof: _proof);
  }

  void signIn() =>
      account.value = projection(generation: 1, signedIn: true, proof: _proof);
  Future<void> completeFresh({
    AccountRoute route = _route,
    int generation = 1,
    bool receipt = true,
    LocalHangarSnapshot value = _fresh,
  }) async {
    fresh.readScope = receipt
        ? LocalHangarReadScope(generation: generation, route: route)
        : null;
    fresh.reads.last.complete(value);
    await Future<void>.delayed(Duration.zero);
  }

  void dispose() {
    display.dispose();
    account.dispose();
  }
}

void main() {
  for (final forbidden in [false, true]) {
    test(
      'metadata edit still accepts newer inventory and honors access failure: $forbidden',
      () async {
        final h = _Harness();
        addTearDown(h.dispose);
        await h.load();
        h.handoff();
        h.signIn();
        await h.completeFresh();
        final pending = h.display.read();
        await h.display.savePersonalData(
          'ship',
          '北辰',
          '备注',
          1,
          operationId: 'test',
        );
        if (forbidden) {
          final rejected = expectLater(
            pending,
            throwsA(isA<LocalHangarFailure>()),
          );
          h.fresh.reads.last.completeError(
            const LocalHangarFailure('hangar.forbidden'),
          );
          await rejected;
          expect(h.display.snapshot, isNull);
          expect(h.display.confirmed, isFalse);
        } else {
          h.fresh.reads.last.complete(
            const LocalHangarSnapshot(
              revision: 3,
              ships: [
                LocalHangarShip(
                  id: 'ship',
                  title: 'New inventory',
                  nickname: '新资料',
                ),
              ],
            ),
          );
          expect((await pending).revision, 3);
          expect(h.display.snapshot!.ships.single.nickname, '新资料');
        }
      },
    );
  }
  for (final failed in [false, true]) {
    test(
      'text edit receipt and media survive older refresh, failed: $failed',
      () async {
        final h = _Harness();
        addTearDown(h.dispose);
        await h.load();
        h.handoff();
        h.signIn();
        await h.completeFresh();
        final epoch = h.display.contentEpoch;
        final stale = h.display.read();
        final saved = await h.display.savePersonalData(
          'ship',
          '北辰',
          '备注',
          1,
          operationId: 'test',
        );
        expect(h.display.contentEpoch, epoch);
        if (failed) {
          h.fresh.reads.last.completeError(
            const LocalHangarFailure('hangar.storage_busy', retryable: true),
          );
        } else {
          h.fresh.reads.last.complete(_fresh);
        }
        expect(await stale, same(saved));
        expect(h.display.snapshot!.ships.single.nickname, '北辰');
        expect(h.display.contentEpoch, epoch);
        h.account.value = projection(generation: 2);
        expect(h.display.personalDataAvailable, isFalse);
        await expectLater(
          h.display.savePersonalData('ship', 'x', null, 2, operationId: 'late'),
          throwsA(isA<LocalHangarFailure>()),
        );
      },
    );
  }
  for (final late in [false, true]) {
    test(
      'an issued image lease cannot survive owner retirement, pending: $late',
      () async {
        final h = _Harness();
        addTearDown(h.dispose);
        await h.load();
        h.handoff();
        h.signIn();
        await h.completeFresh();
        final image = h.display.imageFor('ship', 1)!;
        Future<void>? rejected;
        if (late) {
          h.fresh.image.pending = Completer<String?>();
          rejected = expectLater(
            image.readImage(),
            throwsA(isA<LocalHangarFailure>()),
          );
        }
        h.account.value = projection(generation: 2);
        expect(image.canPickLogo, isFalse);
        if (late) {
          h.fresh.image.pending!.complete('old image');
          await rejected;
        } else {
          await expectLater(
            image.readImage(),
            throwsA(isA<LocalHangarFailure>()),
          );
        }
        expect(h.fresh.image.reads, late ? 1 : 0);
        expect(h.display.snapshot, isNull);
      },
    );
  }
  for (final boundary in [
    'missing',
    'different',
    'skipped',
    'proofLost',
    'logout',
    'unmaterialized',
    'lateReadonly',
  ]) {
    test('$boundary retires cached hangar and ignores late results', () async {
      final h = _Harness();
      addTearDown(h.dispose);
      Future<LocalHangarSnapshot>? old;
      if (boundary == 'unmaterialized' || boundary == 'lateReadonly') {
        old = h.display.read();
      } else {
        await h.load();
      }
      if (boundary == 'different') {
        h.account.value = projection(
          proof: const AccountDisplayHandoff(
            displayKey: 'f0000000000000000000000000000000',
            sourceGeneration: 0,
            route: _route,
          ),
        );
      } else if (boundary == 'missing') {
        h.account.value = projection(generation: 1);
      } else if (boundary == 'skipped') {
        h.account.value = projection(generation: 2, proof: _proof);
      } else {
        h.handoff();
        if (boundary == 'proofLost') {
          h.signIn();
          h.account.value = projection(generation: 1, signedIn: true);
          await h.completeFresh();
        } else if (boundary == 'logout') {
          h.account.value = projection(generation: 2);
        }
      }
      if (old != null) {
        final rejected = expectLater(old, throwsA(isA<LocalHangarFailure>()));
        h.cached.reads.single.complete(_cached);
        await rejected;
      }
      expect(h.display.snapshot, isNull);
      expect(h.display.confirmed, isFalse);
      expect(h.cached.writes + h.fresh.writes, 0);
    });
  }
  for (final boundary in ['owner', 'generation', 'missingReceipt']) {
    test(
      'fresh $boundary mismatch never promotes readonly rows or writes',
      () async {
        final h = _Harness();
        addTearDown(h.dispose);
        await h.load();
        h.handoff();
        h.signIn();
        expect(h.display.favoritesAvailable, isFalse);
        await expectLater(
          h.display.setFavorite('ship', true, 7),
          throwsA(isA<LocalHangarFailure>()),
        );
        await h.completeFresh(
          route: boundary == 'owner'
              ? const AccountRoute(
                  environment: 'integration',
                  authority: 'synthetic',
                  subject: 'other',
                )
              : _route,
          generation: boundary == 'generation' ? 2 : 1,
          receipt: boundary != 'missingReceipt',
        );
        expect(h.display.snapshot, isNull);
        expect(h.display.confirmed, isFalse);
        expect(h.fresh.writes, 0);
      },
    );
  }
  for (final recoverable in [true, false]) {
    test(
      'fresh failure preserves display only when classified recoverable: $recoverable',
      () async {
        final h = _Harness();
        addTearDown(h.dispose);
        await h.load();
        h.handoff();
        h.signIn();
        h.fresh.reads.single.completeError(
          LocalHangarFailure(
            recoverable ? 'hangar.read_unavailable' : 'hangar.forbidden',
            retryable: recoverable,
          ),
        );
        await Future<void>.delayed(Duration.zero);
        expect(h.display.failed, isTrue);
        expect(h.display.snapshot != null, recoverable);
        expect(h.display.confirmed, isFalse);
        final pending = h.display.read();
        await h.completeFresh();
        await pending;
        expect(h.display.snapshot!.revision, 1);
        expect(h.display.snapshot!.ships.single.title, 'Fresh ship');
        expect(h.display.confirmed, isTrue);
      },
    );
  }
  test('fresh same-owner empty snapshot replaces cached higher revision and proof-only removal preserves it', () async {
    final h = _Harness();
    addTearDown(h.dispose);
    await h.load();
    final view = h.display.view;
    h.handoff();
    expect(h.display.snapshot!.revision, 7);
    expect(h.display.canRefresh, isFalse);
    expect(h.cached.reads, hasLength(1));
    expect(h.fresh.reads, isEmpty);
    h.signIn();
    await h.completeFresh(
      value: const LocalHangarSnapshot(revision: 0, ships: []),
    );
    h.account.value = projection(generation: 1, signedIn: true);
    expect(h.display.snapshot!.revision, 0);
    expect(h.display.snapshot!.ships, isEmpty);
    expect(h.display.confirmed, isTrue);
    expect(h.display.view, same(view));
    expect(h.display.view.scrollOffset, 300);
    expect(h.display.view.query, 'ship');
    expect(h.fresh.reads, hasLength(1));
  });
  test('a changed proof owner cannot retain already fresh inventory at the same generation', () async {
    final h = _Harness();
    addTearDown(h.dispose);
    await h.load();
    h.handoff();
    h.signIn();
    await h.completeFresh();
    h.account.value = projection(
      generation: 1,
      signedIn: true,
      proof: const AccountDisplayHandoff(
        displayKey: _id,
        sourceGeneration: 0,
        route: AccountRoute(
          environment: 'integration',
          authority: 'synthetic',
          subject: 'other',
        ),
      ),
    );
    expect(h.display.snapshot, isNull);
    expect(h.display.confirmed, isFalse);
  });
}
