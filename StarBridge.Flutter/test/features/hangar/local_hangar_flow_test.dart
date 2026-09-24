import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/account/account_module.dart';
import 'package:starbridge_flutter/features/account/account_models.dart';
import 'package:starbridge_flutter/app/routing/open_destination_intent.dart';
import 'package:starbridge_flutter/features/account/in_memory_account_adapter.dart';
import 'package:starbridge_flutter/features/hangar/hangar_page.dart';
import 'package:starbridge_flutter/features/hangar/local_hangar_port.dart';

import 'hangar_reader_test.dart' as fixtures;

void main() {
  testWidgets(
    'legacy sign-in opens the saved hangar without SCM authorization',
    (tester) async {
      final adapter = InMemoryAccountAdapter(
        initial: const AccountHostSnapshot(
          generation: 3,
          sessionState: AccountSessionState.legacySignedIn,
          profileFreshness: AccountProfileFreshness.unavailable,
          identity: AccountIdentityProjection.unavailable(),
          compatibility: AccountCompatibilityProjection.unavailable(),
          localeOptions: [],
          timeZoneOptions: [],
        ),
      );
      final account = createAccountModule(adapter);
      await account.initialize();
      final port = FlowPort();
      final browser = fixtures.BrowserFake();
      await tester.pumpWidget(
        fixtures.app(
          HangarPage(
            account: account,
            previewFactory: () => fixtures.PreviewFake(),
            browserFactory: () => browser,
            localFactory: () => port,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('local-hangar-read')), findsOneWidget);
      expect(find.byKey(const Key('hangar-open-reader')), findsNothing);
      expect(adapter.commands, isEmpty);
      await tester.tap(find.byKey(const Key('local-hangar-read')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('hangar-reader-action')), findsOneWidget);
      expect(browser.opens, 1);
      await tester.pump();
      expect(browser.opens, 1);
      expect(find.byKey(const Key('hangar-browser-viewport')), findsOneWidget);
      expect(adapter.commands, isEmpty);
      await tester.pumpWidget(const SizedBox());
      account.dispose();
    },
  );
  testWidgets('hangar login navigates to settings without starting SCM', (
    tester,
  ) async {
    final adapter = InMemoryAccountAdapter();
    final account = createAccountModule(adapter);
    await account.initialize();
    String? route;
    await tester.pumpWidget(
      fixtures.app(
        Actions(
          actions: {
            OpenDestinationIntent: CallbackAction<OpenDestinationIntent>(
              onInvoke: (intent) {
                route = intent.route;
                return null;
              },
            ),
          },
          child: HangarPage(
            account: account,
            previewFactory: () => fixtures.PreviewFake(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('hangar-open-reader')));
    expect(route, '/settings/account');
    expect(adapter.commands, isEmpty);
    await tester.pumpWidget(const SizedBox());
    account.dispose();
  });
  testWidgets(
    'normal hangar reads, confirms, returns to saved list and clears on logout',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1056, 720));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final account = createAccountModule(
        InMemoryAccountAdapter.forReview(AccountReviewState.signedIn),
      );
      await account.initialize();
      final port = FlowPort();
      final preview = fixtures.PreviewFake()
        ..results = [
          {...fixtures.result('complete'), 'canSave': true},
        ];
      await tester.pumpWidget(
        fixtures.app(
          HangarPage(
            account: account,
            previewFactory: () => preview,
            browserFactory: () => fixtures.BrowserFake(),
            localFactory: () => port,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('尚未保存机库'), findsOneWidget);
      expect(find.text('测试机库'), findsNothing);
      await tester.tap(find.byKey(const Key('local-hangar-read')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('hangar-reader-action')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('local-hangar-save-panel')), findsOneWidget);
      expect(port.writes, 0);
      await tester.tap(find.byKey(const Key('local-hangar-confirm')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('local-hangar-save')));
      await tester.pumpAndSettle();
      expect(port.writes, 1);
      expect(find.text('测试舰船'), findsOneWidget);
      expect(find.byKey(const Key('local-hangar-save-panel')), findsNothing);
      await account.logout();
      await tester.pumpAndSettle();
      expect(find.text('测试舰船'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      account.dispose();
    },
  );
}

class FlowPort implements LocalHangarPort {
  int writes = 0;
  LocalHangarSnapshot snapshot = const LocalHangarSnapshot(
    revision: 0,
    ships: [],
  );
  @override
  Future<LocalHangarSnapshot> read() async => snapshot;
  @override
  Future<LocalHangarSnapshot> save(
    String operationId,
    int expectedRevision, {
    bool confirmEmpty = false,
  }) async {
    writes++;
    snapshot = LocalHangarSnapshot(
      revision: 1,
      operationId: operationId,
      savedAt: DateTime.now(),
      ships: const [
        LocalHangarShip(id: 'local-ship', title: 'Test Ship', cn: '测试舰船'),
      ],
    );
    return snapshot;
  }
}
