import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/app/feature_registry.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_feature.dart';
import 'package:starbridge_flutter/features/account/account_models.dart';
import 'package:starbridge_flutter/features/onboarding/connection_mode_port.dart';
import 'package:starbridge_flutter/features/personal_profile/in_memory_personal_profile_adapter.dart';
import 'package:starbridge_flutter/features/personal_profile/offline_personal_profile_page.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_local_projection.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_models.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_module.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_page.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_port.dart';
import 'package:starbridge_flutter/features/personal_profile/profile_read_scope.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_visibility.dart';

import '../../app/tray_quick_panel_test.dart' show app;

const _id = '0123456789abcdef0123456789abcdef';
const _route = AccountRoute(
  environment: 'integration',
  authority: 'synthetic',
  subject: 'profile-owner',
);
const _proof = AccountDisplayHandoff(
  displayKey: _id,
  sourceGeneration: 7,
  route: _route,
);
final _savedAt = DateTime.utc(2026, 10, 1, 12);

AccountProjection _account({
  bool prepared = false,
  AccountDisplayHandoff? proof,
}) => AccountProjection(
  generation: prepared ? 7 : 8,
  sessionState: prepared
      ? AccountSessionState.loading
      : AccountSessionState.signedIn,
  operation: prepared ? AccountOperation.refreshing : AccountOperation.none,
  preparingDisplay: true,
  profileFreshness: AccountProfileFreshness.cached,
  cachedAt: _savedAt,
  retainedReadId: prepared ? _id : null,
  displayHandoff: proof,
  identity: const AccountIdentityProjection.unavailable(),
  compatibility: const AccountCompatibilityProjection.unavailable(),
  localeOptions: const [],
  timeZoneOptions: const [],
);

class _Mode extends ChangeNotifier
    implements ConnectionModeControl, ConnectionModeDisplayContinuitySource {
  @override
  ConnectionModeSnapshot snapshot = const ConnectionModeSnapshot(
    scope: 7,
    revision: 4,
    state: ConnectionModeState.online,
  );
  @override
  bool failed = false;
  @override
  OnlineModeDisplayContinuity? displayContinuity;
  @override
  bool get busy => false;
  @override
  bool get allowsOnlineTraffic =>
      !failed && snapshot.state == ConnectionModeState.online;
  @override
  bool get canEnterOffline => false;
  @override
  Future<bool> enterOffline() async => false;
}

// Deliberately synthetic domain scheduling. The original module, page and
// frozen handoff owner below are production code; this is not a Native wire run.
class _Port
    implements
        PersonalProfilePort,
        ProfileReadScopeOwner,
        ProfileReadGenerationOwner,
        ProfileVisibilityAccess {
  _Port({this.cached = false});
  final bool cached;
  bool local = false;
  final hard = StreamController<void>.broadcast(sync: true);
  Completer<PersonalProfileSnapshot>? pending = Completer();
  int reads = 0, saves = 0;
  Completer<PersonalProfileActionResult>? saveGate;
  PersonalProfileEdit? savedEdit;
  Completer<ProfileVisibilityState>? visibilityGate;
  @override
  Future<ProfileVisibilityState> readVisibility() async =>
      visibilityGate == null
      ? const ProfileVisibilityState(1, PersonalProfileVisibility.onlyMe)
      : visibilityGate!.future;
  @override
  Future<ProfileVisibilityState> saveVisibility(
    ProfileVisibilityState expected,
    PersonalProfileVisibility visibility,
  ) async => ProfileVisibilityState(expected.revision + 1, visibility);
  @override
  ProfileReadScope? readScope;
  @override
  int activeReadGeneration = 8;
  ProfileReadScope nextScope = const ProfileReadScope(8, _route);
  @override
  Stream<void> get invalidations => hard.stream;
  Future<PersonalProfileSnapshot> fresh() async {
    final remote = await InMemoryPersonalProfileAdapter.forReview(
      signedIn: true,
    ).read();
    return local
        ? projectLocalProfile(
            remote,
            {
              'callSign': 'Synthetic Pilot',
              'introduction': 'Existing',
              'avatarStyle': 0,
              'wallpaperId': 'none',
              'modules': [],
              'favoriteShipIds': [],
            },
            null,
            _savedAt,
          )
        : remote;
  }

  @override
  Future<PersonalProfileSnapshot> read() async {
    reads++;
    readScope = null;
    if (cached) {
      return projectLocalProfile(
        await fresh(),
        {
          'callSign': 'Cached synthetic pilot',
          'introduction': 'Cached handoff biography',
          'avatarStyle': 0,
          'wallpaperId': 'none',
          'modules': [],
          'favoriteShipIds': [],
        },
        null,
        _savedAt,
        readOnly: true,
      );
    }
    final result = await pending!.future;
    if (result.availability == PersonalProfileAvailability.available) {
      readScope = nextScope;
    }
    return result;
  }

  @override
  Future<PersonalProfileActionResult> save(PersonalProfileEdit edit) async {
    saves++;
    savedEdit = edit;
    if (saveGate != null) return saveGate!.future;
    return const PersonalProfileActionResult(
      PersonalProfileActionOutcome.rejected,
    );
  }

  @override
  Future<void> close() async => hard.close();
}

class ProfileLifetimeFixture {
  final mode = _Mode(), cache = _Port(cached: true), port = _Port();
  final account = ValueNotifier(_account(prepared: true));
  late final PersonalProfileModule online = createPersonalProfileModule(port);
  FeatureDescriptor? feature;
  late StateSetter navigation;
  bool visible = true;
  Future<void> mountFeature(
    WidgetTester tester, {
    bool authenticated = false,
    bool retained = true,
  }) async {
    await tester.binding.setSurfaceSize(const Size(1280, 650));
    if (!authenticated && !retained) {
      account.value = const AccountProjection.loading().copyWith(generation: 8);
      mode.snapshot = const ConnectionModeSnapshot(
        scope: 8,
        revision: 4,
        state: ConnectionModeState.online,
      );
    }
    if (authenticated) {
      account.value = _account();
      mode.snapshot = const ConnectionModeSnapshot(
        scope: 8,
        revision: 4,
        state: ConnectionModeState.online,
      );
      port.pending!.complete(await port.fresh());
      await online.initialize();
    } else {
      unawaited(online.initialize());
    }
    feature = createPersonalProfileFeature(
      online,
      account: account,
      connectionMode: mode,
      offlineFactory: () => throw StateError('No manual offline read'),
      retainedFactory: (_) => cache,
    );
    await tester.pumpWidget(
      app(
        Builder(
          builder: (context) => Localizations.override(
            context: context,
            delegates: const [AppStringsDelegate()],
            child: MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: true),
              child: StatefulBuilder(
                builder: (context, setter) {
                  navigation = setter;
                  return visible
                      ? feature!.buildDestination(context)
                      : const SizedBox.shrink();
                },
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> leaveAndReturn(WidgetTester tester) async {
    navigation(() => visible = false);
    await tester.pumpAndSettle();
    navigation(() => visible = true);
    await tester.pump();
  }

  Future<void> mount(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 1000));
    unawaited(online.initialize());
    await tester.pumpWidget(
      app(
        Builder(
          builder: (context) => Localizations.override(
            context: context,
            delegates: const [AppStringsDelegate()],
            child: MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: true),
              child: OfflinePersonalProfilePage(
                mode: mode,
                account: account,
                createPort: () => throw StateError('No manual offline read'),
                createRetainedPort: (_) => cache,
                onlineModule: online,
                online: PersonalProfilePage(module: online),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Cached handoff biography'), findsOneWidget);
    account.value = _account(proof: _proof);
    await tester.pumpAndSettle();
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.binding.setSurfaceSize(null);
    feature?.onDispose?.call();
    online.dispose();
    account.dispose();
    mode.dispose();
  }
}

void main() {
  testWidgets(
    'feature lifetime retains materialized handoff after leaving and returning',
    (tester) async {
      final f = ProfileLifetimeFixture();
      try {
        await f.mountFeature(tester);
        expect(find.textContaining('Cached handoff biography'), findsOneWidget);
        f.account.value = _account(proof: _proof);
        await tester.pumpAndSettle();
        await f.leaveAndReturn(tester);
        expect(find.textContaining('Cached handoff biography'), findsOneWidget);
        expect(f.cache.reads, 1);
        expect(f.port.reads, 1);
      } finally {
        await f.close(tester);
      }
    },
  );
  testWidgets(
    'ordinary profile feature restores its actual departure scroll without another read',
    (tester) async {
      final f = ProfileLifetimeFixture();
      try {
        await f.mountFeature(tester, authenticated: true);
        await tester.drag(find.byType(Scrollable).first, const Offset(0, -550));
        await tester.pumpAndSettle();
        final offset = tester
            .state<ScrollableState>(find.byType(Scrollable).first)
            .position
            .pixels;
        expect(offset, greaterThan(100));
        await f.leaveAndReturn(tester);
        await tester.pumpAndSettle();
        expect(
          tester
              .state<ScrollableState>(find.byType(Scrollable).first)
              .position
              .pixels,
          offset,
        );
        expect(f.port.reads, 1);
      } finally {
        await f.close(tester);
      }
    },
  );
  testWidgets(
    'ordinary profile mode failure withdraws private data and editing without another read',
    (tester) async {
      final f = ProfileLifetimeFixture();
      try {
        await f.mountFeature(tester, authenticated: true);
        expect(
          find.byKey(const Key('profile-identity-header')),
          findsOneWidget,
        );
        f.mode.failed = true;
        f.mode.notifyListeners();
        await tester.pump();
        expect(find.byKey(const Key('profile-identity-header')), findsNothing);
        expect(
          tester
              .widget<PersonalProfilePage>(find.byType(PersonalProfilePage))
              .module
              .projection
              .value
              .canEdit,
          isFalse,
        );
        expect(f.port.reads, 1);
      } finally {
        await f.close(tester);
      }
    },
  );
  testWidgets(
    'ordinary profile unsaved draft and original editing lease survive navigation',
    (tester) async {
      final f = ProfileLifetimeFixture();
      try {
        await f.mountFeature(tester, authenticated: true);
        final edit = find.byKey(const Key('profile-edit'));
        await tester.ensureVisible(edit);
        await tester.pumpAndSettle();
        await tester.tap(edit);
        await tester.pumpAndSettle();
        final about = find.byKey(const Key('profile-about-field'));
        await tester.ensureVisible(about);
        await tester.pumpAndSettle();
        await tester.enterText(about, 'Unsaved feature-lifetime draft');
        await f.leaveAndReturn(tester);
        await tester.pumpAndSettle();
        expect(about, findsOneWidget);
        expect(
          tester.widget<TextField>(about).controller!.text,
          'Unsaved feature-lifetime draft',
        );
        expect(f.port.reads, 1);
        expect(f.port.saves, 0);
      } finally {
        await f.close(tester);
      }
    },
  );
  testWidgets('mode-rejected retry never invents a busy read', (tester) async {
    final f = ProfileLifetimeFixture();
    try {
      await f.mount(tester);
      f.mode.failed = true;
      f.mode.notifyListeners();
      await tester.pumpAndSettle();
      final retry = find.byKey(const Key('profile-retry'));
      await tester.ensureVisible(retry);
      await tester.tap(retry);
      await tester.pumpAndSettle();
      expect(
        f.port.reads,
        1,
        reason: 'Unconfirmed mode must not dispatch another read.',
      );
      final projection = tester
          .widget<PersonalProfilePage>(find.byType(PersonalProfilePage))
          .module
          .projection
          .value;
      expect(projection.availability, PersonalProfileAvailability.unavailable);
      expect(
        projection.operation,
        PersonalProfileOperation.none,
        reason: 'Only the actual original reader can publish a busy phase.',
      );
    } finally {
      await f.close(tester);
    }
  });
  testWidgets(
    'hard mode retirement rejects old completion and waits for a complete new read',
    (tester) async {
      final f = ProfileLifetimeFixture();
      try {
        await f.mount(tester);
        f.mode.snapshot = const ConnectionModeSnapshot(
          scope: 99,
          revision: 5,
          state: ConnectionModeState.online,
        );
        f.mode.notifyListeners();
        await tester.pump();
        f.mode.snapshot = const ConnectionModeSnapshot(
          scope: 7,
          revision: 4,
          state: ConnectionModeState.online,
        );
        f.mode.notifyListeners();
        await tester.pump();
        f.port.pending!.complete(await f.port.fresh());
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<PersonalProfilePage>(find.byType(PersonalProfilePage))
              .module
              .projection
              .value
              .availability,
          PersonalProfileAvailability.unavailable,
          reason: 'The old in-flight completion stays retired.',
        );
        f.port.pending = Completer();
        final retry = tester
            .widget<PersonalProfilePage>(find.byType(PersonalProfilePage))
            .module
            .refresh();
        await tester.pump();
        expect(f.port.reads, 2);
        expect(
          tester
              .widget<PersonalProfilePage>(find.byType(PersonalProfilePage))
              .module
              .projection
              .value
              .availability,
          PersonalProfileAvailability.unavailable,
          reason: 'Starting a new read cannot reuse the old completed receipt.',
        );
        f.port.pending!.complete(await f.port.fresh());
        await retry;
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<PersonalProfilePage>(find.byType(PersonalProfilePage))
              .module,
          same(f.online),
        );
        expect(f.online.projection.value.canEdit, isTrue);
      } finally {
        await f.close(tester);
      }
    },
  );
  testWidgets('withdrawn profile retry stays static under reduced motion', (
    tester,
  ) async {
    final f = ProfileLifetimeFixture();
    try {
      await f.mount(tester);
      f.port.pending!.complete(const PersonalProfileSnapshot.unavailable());
      await tester.pumpAndSettle();
      f.port.pending = Completer();
      final retry = tester
          .widget<PersonalProfilePage>(find.byType(PersonalProfilePage))
          .module
          .refresh();
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(f.port.reads, 2);
      f.port.pending!.complete(await f.port.fresh());
      await retry;
      await tester.pumpAndSettle();
      expect(f.port.saves, 0);
    } finally {
      await f.close(tester);
    }
  });
  for (final continuity in [true, false]) {
    testWidgets(
      'profile mode continuity=$continuity retains only proven readonly display',
      (tester) async {
        final f = ProfileLifetimeFixture();
        try {
          await f.mount(tester);
          f.mode.displayContinuity = continuity
              ? const OnlineModeDisplayContinuity(
                  sourceGeneration: 7,
                  generation: 8,
                  revision: 4,
                )
              : null;
          f.mode.snapshot = continuity
              ? const ConnectionModeSnapshot(
                  scope: 8,
                  state: ConnectionModeState.unavailable,
                )
              : const ConnectionModeSnapshot(
                  scope: 99,
                  revision: 5,
                  state: ConnectionModeState.online,
                );
          f.mode.notifyListeners();
          await tester.pump();
          expect(
            find.textContaining('Cached handoff biography'),
            continuity ? findsOneWidget : findsNothing,
          );
          expect(f.port.reads, 1);
          expect(f.port.saves, 0);
        } finally {
          await f.close(tester);
        }
      },
    );
  }
  testWidgets(
    'a matching fresh profile remains the same page when only display proof is removed',
    (tester) async {
      final f = ProfileLifetimeFixture();
      try {
        await f.mount(tester);
        f.port.pending!.complete(await f.port.fresh());
        await tester.pumpAndSettle();
        final element = tester.element(find.byType(PersonalProfilePage));
        f.account.value = _account();
        await tester.pumpAndSettle();
        expect(tester.element(find.byType(PersonalProfilePage)), same(element));
        expect(
          tester
              .widget<PersonalProfilePage>(find.byType(PersonalProfilePage))
              .module,
          same(f.online),
        );
        expect(f.port.reads, 1);
      } finally {
        await f.close(tester);
      }
    },
  );
  testWidgets(
    'wrong owner receipt withdraws both cached and unverified fresh profile',
    (tester) async {
      final f = ProfileLifetimeFixture();
      try {
        await f.mount(tester);
        f.port.nextScope = const ProfileReadScope(
          8,
          AccountRoute(
            environment: 'integration',
            authority: 'synthetic',
            subject: 'other-owner',
          ),
        );
        f.port.pending!.complete(await f.port.fresh());
        await tester.pumpAndSettle();
        expect(find.textContaining('Cached handoff biography'), findsNothing);
        final page = tester.widget<PersonalProfilePage>(
          find.byType(PersonalProfilePage),
        );
        expect(
          page.module.projection.value.availability,
          PersonalProfileAvailability.unavailable,
        );
        expect(page.module.projection.value.canEdit, isFalse);
      } finally {
        await f.close(tester);
      }
    },
  );
  for (final transient in [true, false]) {
    testWidgets('handoff read failure is classified: transient=$transient', (
      tester,
    ) async {
      final f = ProfileLifetimeFixture();
      try {
        await f.mount(tester);
        f.port.pending!.complete(
          PersonalProfileSnapshot.unavailable(transientReadFailure: transient),
        );
        await tester.pumpAndSettle();
        if (transient) {
          final page = tester.widget<PersonalProfilePage>(
            find.byType(PersonalProfilePage),
          );
          expect(
            page.module.projection.value.operation,
            PersonalProfileOperation.none,
          );
          expect(
            find.textContaining('Cached handoff biography'),
            findsOneWidget,
          );
          expect(find.byKey(const Key('profile-sync-failed')), findsOneWidget);
          expect(page.module.projection.value.canEdit, isFalse);
          final retryButton = find.byKey(const Key('profile-sync-retry'));
          expect(retryButton, findsOneWidget);
          f.port.pending = Completer();
          await tester.ensureVisible(retryButton);
          await tester.tap(retryButton);
          await tester.pump();
          expect(
            f.port.reads,
            2,
            reason: 'Retry must call the existing online module exactly once.',
          );
          await page.module.refresh();
          expect(f.port.reads, 2);
          f.port.pending!.complete(await f.port.fresh());
          await tester.pumpAndSettle();
          expect(find.textContaining('Cached handoff biography'), findsNothing);
          expect(
            tester
                .widget<PersonalProfilePage>(find.byType(PersonalProfilePage))
                .module,
            same(f.online),
          );
          expect(f.online.projection.value.canEdit, isTrue);
        } else {
          expect(find.textContaining('Cached handoff biography'), findsNothing);
          expect(find.byKey(const Key('profile-sync-failed')), findsNothing);
        }
        expect(f.cache.reads, 1);
        expect(f.port.saves, 0);
      } finally {
        await f.close(tester);
      }
    });
  }

  testWidgets(
    'same-generation replacement proof cannot retain the previous private profile',
    (tester) async {
      final f = ProfileLifetimeFixture();
      try {
        await f.mount(tester);
        f.account.value = _account(
          proof: const AccountDisplayHandoff(
            displayKey: _id,
            sourceGeneration: 7,
            route: AccountRoute(
              environment: 'integration',
              authority: 'synthetic',
              subject: 'other-owner',
            ),
          ),
        );
        await tester.pump();
        expect(find.textContaining('Cached handoff biography'), findsNothing);
      } finally {
        await f.close(tester);
      }
    },
  );

  testWidgets(
    'cached handoff synchronization time is the saved observation, not page entry',
    (tester) async {
      final f = ProfileLifetimeFixture();
      try {
        await f.mount(tester);
        final page = tester.widget<PersonalProfilePage>(
          find.byType(PersonalProfilePage),
        );
        expect(page.module.projection.value.synchronizedAtUtc, _savedAt);
      } finally {
        await f.close(tester);
      }
    },
  );
}
