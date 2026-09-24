import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/communities/communities_module.dart';
import 'package:starbridge_flutter/features/communities/community_profile_controller.dart';
import 'package:starbridge_flutter/features/communities/community_workspace_port.dart';
import 'package:starbridge_flutter/features/communities/example_communities.dart';

import 'community_workspace_view_test.dart' show host;
import 'community_image_test_support.dart';

const owner = '00000000000000000000000000000002';
const member = '00000000000000000000000000000001';
void main() {
  late ExampleCommunities port;
  setUp(() => port = ExampleCommunities());
  tearDown(() => port.close());
  test('opening editor alone never changes directory data', () async {
    final before = (await port.read(view: 'mine', query: '')).items;
    await port.readProfile(targetRef: owner);
    final after = (await port.read(view: 'mine', query: '')).items;
    for (var i = 0; i < before.length; i++) {
      expect(after[i].description, before[i].description);
      expect(after[i].systems, before[i].systems);
      expect(after[i].recruiting, before[i].recruiting);
      expect(after[i].joinMode, before[i].joinMode);
    }
  });
  test(
    'existing controller saves and rereads; all other memberships remain',
    () async {
      final editor = CommunityProfileController(port, owner);
      addTearDown(editor.dispose);
      await editor.load();
      expect(editor.error, isNull);
      editor.update('description', '新的示例简介');
      editor.update('language', '中文');
      editor.update('activeSystemIds', ['nyx']);
      editor.update('externalContacts', [
        {'platform': 'Discord', 'value': 'example-only'},
      ]);
      editor.update('activityWindows', [
        {
          'days': ['fri'],
          'startTime': '22:00',
          'endTime': '02:00',
          'endsNextDay': true,
        },
      ]);
      await editor.save();
      expect(editor.outcome?.status, 'accepted');
      expect(editor.dirty, isFalse);
      final workspace = await port.readWorkspace(owner, '', 0);
      expect(workspace.description, '新的示例简介');
      expect(workspace.externalContacts, [('Discord', 'example-only')]);
      expect(workspace.activityWindows.single.endsNextDay, isTrue);
      final directory = await port.read(view: 'mine', query: '');
      expect(directory.items, hasLength(2));
      expect(directory.items.singleWhere((r) => r.targetRef == owner).systems, [
        'Nyx',
      ]);
      expect(
        (await port.readWorkspace(member, '', 0)).description,
        isNot('新的示例简介'),
      );
    },
  );
  test('discard and a fresh example session do not retain edits', () async {
    final editor = CommunityProfileController(port, owner);
    addTearDown(editor.dispose);
    await editor.load();
    editor.update('description', 'discard this');
    editor.discard();
    await editor.save();
    expect(
      (await port.readWorkspace(owner, '', 0)).description,
      isNot('discard this'),
    );
    editor.update('description', 'session only');
    await editor.save();
    final fresh = ExampleCommunities();
    addTearDown(fresh.close);
    expect(
      (await fresh.readWorkspace(owner, '', 0)).description,
      isNot('session only'),
    );
  });
  test(
    'member cannot edit; stale editor cannot overwrite a newer save',
    () async {
      await expectLater(
        port.readProfile(targetRef: member),
        throwsA(isA<CommunityFailure>()),
      );
      final first = await port.readProfile(targetRef: owner);
      final second = await port.readProfile(targetRef: owner);
      expect(
        (await port.saveProfile('a' * 32, first.editRef, {
          'description': 'first',
        })).status,
        'accepted',
      );
      expect(
        (await port.saveProfile('b' * 32, second.editRef, {
          'description': 'second',
        })).error,
        'conflict',
      );
      expect((await port.readWorkspace(owner, '', 0)).description, 'first');
    },
  );
  test('invalid mixed changes never partially publish', () async {
    final profile = await port.readProfile(targetRef: owner);
    final result = await port.saveProfile('a' * 32, profile.editRef, {
      'description': 'must not publish',
      'code': 'immutable',
    });
    expect(result.error, 'dataInvalid');
    expect(
      (await port.readWorkspace(owner, '', 0)).description,
      isNot('must not publish'),
    );
    expect((await port.readProfile(editRef: profile.editRef)).revision, 0);
  });
  test('saved logo uses scoped media; clear and close revoke it', () async {
    final profile = await port.readProfile(targetRef: owner);
    final bytes = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/lxoAAAAASUVORK5CYII=',
    );
    final result = await port.saveProfile('a' * 32, profile.editRef, {
      'logoImageData': 'data:image/png;base64,${base64Encode(bytes)}',
    });
    expect(result.status, 'accepted');
    expect((await port.readWorkspace(owner, '', 0)).hasLogo, isTrue);
    final received = await assembleCommunityMedia(
      (offset, version) =>
          port.readMedia(owner, 'logo', offset: offset, version: version),
      'logo',
      checkCurrent: () {},
    );
    expect(received, bytes);
    await expectLater(
      port.readMedia(member, 'logo', offset: 0),
      throwsA(isA<CommunityFailure>()),
    );
    final next = await port.readProfile(editRef: profile.editRef);
    await port.saveProfile('b' * 32, next.editRef, {'clearLogoImage': true});
    expect((await port.readWorkspace(owner, '', 0)).hasLogo, isFalse);
    await port.close();
    expect(
      (await port.saveProfile('c' * 32, next.editRef, {
        'description': 'late',
      })).error,
      'identityUnavailable',
    );
  });
  testWidgets(
    'actual workspace opens the existing profile editor and saves back',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 1050);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        host(port, const Locale('zh', 'CN'), target: owner),
      );
      await settleCommunityImages(tester);
      await tester.tap(find.byKey(const ValueKey('community-section-manage')));
      await settleCommunityImages(tester);
      await tester.tap(find.byKey(const ValueKey('settings-nav-profile')));
      await settleCommunityImages(tester);
      final field = find.byWidgetPredicate(
        (w) => w is TextFormField && w.key.toString().contains('-description'),
      );
      await tester.enterText(field, '界面保存后的示例简介');
      await settleCommunityImages(tester);
      await tester.tap(find.widgetWithText(FilledButton, '保存更改'));
      await settleCommunityImages(tester);
      expect(
        (await port.readWorkspace(owner, '', 0)).description,
        '界面保存后的示例简介',
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
