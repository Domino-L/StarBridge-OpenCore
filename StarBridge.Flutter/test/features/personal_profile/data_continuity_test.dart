import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_module.dart';
import 'package:starbridge_flutter/features/personal_profile/bridge_personal_profile_adapter.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_page.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_models.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_presentation.dart';

import 'local_personal_profile_test.dart' as support;
import '../gameplay_time/gameplay_time_test.dart' as gameplay;

void main() {
  testWidgets('verified never-saved page remains editable for owner', (
    tester,
  ) async {
    final payload = <String, Object?>{
      'schemaVersion': 1,
      'editable': true,
      'profile': {
        'schemaVersion': 3,
        'revision': 0,
        'updatedAt': '1970-01-01T00:00:00Z',
        'visibility': 'private',
        'identity': {
          'callSign': 'SyntheticPilot',
          'gameHandle': 'SyntheticPilot',
        },
        'content': {},
      },
    };
    final snapshot = parsePersonalProfileSnapshot(payload);
    expect(snapshot.defaultedPage, isTrue);
    for (final profile in [
      {...(payload['profile']! as Map<String, Object?>), 'revision': 1},
      {...(payload['profile']! as Map<String, Object?>), 'updatedAt': null},
      {
        ...(payload['profile']! as Map<String, Object?>),
        'updatedAt': 'invalid',
      },
    ]) {
      expect(
        parsePersonalProfileSnapshot({...payload, 'profile': profile})
            .defaultedPage,
        isFalse,
      );
    }
    final h = support.Harness();
    h.remote.importedSnapshot = snapshot;
    final module = createPersonalProfileModule(h.port);
    await tester.runAsync(module.initialize);
    await tester.pumpWidget(_app(PersonalProfilePage(module: module)));
    await tester.pumpAndSettle();
    expect(find.text('这个账号还没有保存过个人页'), findsOneWidget);
    expect(find.byKey(const Key('profile-edit')), findsOneWidget);
    await tester.pumpWidget(
      _app(
        PersonalProfilePage(
          key: const Key('visitor'),
          module: module,
          isVisitor: true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('这个账号还没有保存过个人页'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    module.dispose();
    await tester.runAsync(h.close);
  });

  for (final legacy in [false, true]) {
    testWidgets(
      'owner read failure blocks editing and retry recovers: legacy=$legacy',
      (tester) async {
        final h = support.Harness(legacy: legacy);
        h.remote.readError = StateError('synthetic read failure');
        final module = createPersonalProfileModule(h.port);
        await tester.runAsync(module.initialize);
        await tester.pumpWidget(_app(PersonalProfilePage(module: module)));
        await tester.pumpAndSettle();
        expect(find.text('暂时读不到你的个人页，稍后重试'), findsOneWidget);
        expect(find.text('重试'), findsOneWidget);
        expect(find.byKey(const Key('profile-edit')), findsNothing);
        expect(module.projection.value.allowEditing, isFalse);
        final writes = h.connection.requests
            .where((r) => r.name == 'personalProfile.localSave')
            .length;
        expect(
          (await h.port.save(support.edit(await h.port.read()))).outcome,
          PersonalProfileActionOutcome.rejected,
        );
        expect(
          h.connection.requests
              .where((r) => r.name == 'personalProfile.localSave')
              .length,
          writes,
        );
        h.remote.readError = null;
        await tester.tap(find.byKey(const Key('profile-retry')));
        await tester.pumpAndSettle();
        expect(find.text('暂时读不到你的个人页，稍后重试'), findsNothing);
        expect(find.byKey(const Key('profile-edit')), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
        module.dispose();
        await tester.runAsync(h.close);
      },
    );
  }

  test('only local save carries device-only success copy', () async {
    final h = support.Harness();
    addTearDown(h.close);
    var snapshot = await h.port.read();
    expect(snapshot.local!.localOnlyEdits, isTrue);
    final saved = await h.port.save(
      support.edit(snapshot, callSign: snapshot.callSign),
    );
    expect(saved.outcome, PersonalProfileActionOutcome.completed);
    expect(saved.messageKey, 'profile.local.onlySaved');
    h.remote.presentation = PersonalProfilePresentation.fromProfile({
      'revision': 4,
      'avatarStyle': 0,
      'wallpaperId': 'none',
      'content': {},
      'presentation': {
        'schemaVersion': 1,
        'sourceVersion': 'a' * 64,
        'origins': {
          for (final group in PersonalProfilePresentation.groups)
            group: 'default',
        },
      },
    });
    snapshot = await h.port.read();
    expect(snapshot.local!.localOnlyEdits, isFalse);
    final remoteSaved = await h.port.save(
      support.edit(snapshot, callSign: snapshot.callSign),
    );
    expect(remoteSaved.outcome, PersonalProfileActionOutcome.completed);
    expect(remoteSaved.messageKey, isNull);
  });

  testWidgets(
    'local edit description and success are shown only for local branch',
    (tester) async {
      final h = support.Harness();
      final module = createPersonalProfileModule(h.port);
      await tester.runAsync(module.initialize);
      await tester.pumpWidget(_app(PersonalProfilePage(module: module)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('profile-edit')));
      await tester.pumpAndSettle();
      expect(find.text('这些改动只保存在这台电脑上，换电脑后看不到。'), findsOneWidget);
      final save = find.byKey(const Key('profile-save'));
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('profile-editor-panel')), findsNothing);
      expect(find.text('这些改动只保存在这台电脑上，换电脑后看不到。'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      module.dispose();
      await tester.runAsync(h.close);
    },
  );

  testWidgets('visitor sees none of the owner storage notices', (tester) async {
    final h = support.Harness();
    final module = createPersonalProfileModule(h.port);
    await tester.runAsync(module.initialize);
    await tester.pumpWidget(
      _app(PersonalProfilePage(module: module, isVisitor: true)),
    );
    await tester.pumpAndSettle();
    for (final text in [
      '这些改动只保存在这台电脑上，换电脑后看不到。',
      '本机累计只保存在这台电脑上。',
      '账号累计暂时读不到',
      '暂时读不到你的个人页，稍后重试',
    ]) {
      expect(find.text(text), findsNothing);
    }
    await tester.pumpWidget(const SizedBox());
    module.dispose();
    await tester.runAsync(h.close);
  });
}

Widget _app(Widget child) => gameplay.app(SizedBox(height: 1100, child: child));
