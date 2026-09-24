import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/features/account/account_module.dart';
import 'package:starbridge_flutter/features/account/in_memory_account_adapter.dart';
import 'package:starbridge_flutter/features/communities/community_hangar_sharing_dialog.dart';
import 'package:starbridge_flutter/features/communities/community_hangar_sharing_port.dart';
import 'package:starbridge_flutter/features/hangar/hangar_feature.dart';

import 'hangar_reader_test.dart' as fixtures;
import 'local_hangar_flow_test.dart' show FlowPort;

void main() {
  testWidgets(
    'personal hangar reuses audience editor and closes it on logout',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(420, 720));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final account = createAccountModule(
        InMemoryAccountAdapter.forReview(AccountReviewState.signedIn),
      );
      await account.initialize();
      final port = _SharingPort();
      final local = FlowPort();
      addTearDown(port.changes.close);
      final feature = createHangarFeature(
        account,
        () => fixtures.PreviewFake(),
        localFactory: () => local,
        sharingPort: port,
      );
      await tester.pumpWidget(_app(Builder(builder: feature.buildDestination)));
      await tester.pumpAndSettle();
      final entry = find.byKey(const Key('local-hangar-sharing'));
      expect(entry, findsOneWidget);
      expect(tester.getRect(entry).right, lessThanOrEqualTo(420));
      expect(port.reads, 0);
      expect(port.writes, 0);
      await tester.tap(entry);
      await tester.pumpAndSettle();
      expect(find.byType(CommunityHangarSharingDialog), findsOneWidget);
      expect(port.reads, 1);
      expect(port.writes, 0);
      await tester.tap(find.text('Org B'));
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, '保存共享范围'));
      await tester.pumpAndSettle();
      expect(port.writes, 1);
      expect(local.writes, 0);
      expect(port.selected, ['b' * 32]);
      await tester.tap(entry);
      await tester.pumpAndSettle();
      expect(
        tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
        isTrue,
      );
      await account.logout();
      await tester.pumpAndSettle();
      expect(find.byType(CommunityHangarSharingDialog), findsNothing);
      expect(entry, findsNothing);
      expect(port.writes, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      account.dispose();
    },
  );

  testWidgets('missing sharing capability does not expose a dead entry', (
    tester,
  ) async {
    final account = createAccountModule(
      InMemoryAccountAdapter.forReview(AccountReviewState.signedIn),
    );
    await account.initialize();
    final port = _SharingPort()..hangarSharingAvailable = false;
    addTearDown(port.changes.close);
    final feature = createHangarFeature(
      account,
      () => fixtures.PreviewFake(),
      localFactory: () => FlowPort(),
      sharingPort: port,
    );
    await tester.pumpWidget(_app(Builder(builder: feature.buildDestination)));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('local-hangar-sharing')), findsNothing);
    expect(port.reads, 0);
    expect(port.writes, 0);
    await tester.pumpWidget(const SizedBox());
    account.dispose();
  });
}

Widget _app(Widget child) {
  final base = fixtures.app(child) as MaterialApp;
  return MaterialApp(
    theme: base.theme,
    locale: const Locale('zh', 'CN'),
    supportedLocales: AppStrings.supportedLocales,
    localizationsDelegates: const [
      AppStringsDelegate(),
      ...GlobalMaterialLocalizations.delegates,
    ],
    home: base.home,
  );
}

class _SharingPort implements CommunityHangarSharingPort {
  final changes = StreamController<void>.broadcast();
  @override
  Stream<void> get invalidations => changes.stream;
  @override
  bool hangarSharingAvailable = true;
  int reads = 0, writes = 0;
  List<String> selected = [];
  @override
  Future<CommunityHangarSharing> readHangarSharing() async {
    reads++;
    return CommunityHangarSharing.parse({
      'schemaVersion': 1,
      'maximumTargets': 64,
      'editRef': 'a' * 32,
      'usesExplicitTargets': true,
      'options': [
        {
          'targetRef': 'b' * 32,
          'name': 'Org B',
          'selected': selected.isNotEmpty,
        },
      ],
    });
  }

  @override
  Future<CommunityHangarSharingOutcome> saveHangarSharing(
    String editRef,
    List<String> selectedRefs,
  ) async {
    writes++;
    selected = List.of(selectedRefs);
    return const CommunityHangarSharingOutcome('accepted');
  }
}
