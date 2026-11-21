import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_profile_view.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_identity_header.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_models.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_module_grid.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_presentation.dart';

import '../../app/menu_overlay/menu_profiles_session_test.dart'
    show fixtureProfile;
import '../gameplay_time/gameplay_time_test.dart' as support;

void main() {
  test('visitor provenance accepts a redacted owner source fingerprint', () {
    final presentation = PersonalProfilePresentation.fromProfile({
      'revision': 7,
      'avatarStyle': 0,
      'wallpaperId': 'none',
      'presentation': {
        'schemaVersion': 1,
        'sourceVersion': null,
        'origins': {
          for (final group in PersonalProfilePresentation.groups)
            group: group == 'schedule' ? 'unknown' : 'linkedLegacy',
        },
      },
      'content': {'introduction': 'Published introduction'},
    })!;
    expect(presentation.sourceVersion, isNull);
    expect(presentation.origins['introduction'], 'linkedLegacy');
    expect(presentation.origins['schedule'], 'unknown');
    expect(presentation.content['introduction'], 'Published introduction');
  });

  final profile = PersonalProfileProjection.fromSnapshot(
    MenuProfileView.parse({
      ...MenuProfileView.encode(fixtureProfile),
      'name': 'Chosen public callsign',
      'about': '',
      'affiliations': <Object?>[],
      'minutes': null,
      'modules': <Object?>[],
    }).snapshot!,
  );

  for (final width in [600.0, 1280.0]) {
    testWidgets(
      'visitor empty fields do not assert owner never filled them: $width',
      (tester) async {
        await tester.binding.setSurfaceSize(Size(width, 1000));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          support.app(
            Column(
              children: [
                PersonalProfileIdentityHeader(
                  projection: profile,
                  isSelf: false,
                ),
                // User 11-11: playtime lives in the side rail, not the column.
                PersonalProfileModuleGrid(
                  projection: profile,
                  visitorView: true,
                  editing: false,
                  layout: const [],
                  onLayoutChanged: (_) => fail('Visitor must not edit'),
                ),
              ],
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Chosen public callsign'), findsOneWidget);
        expect(find.text('当前页面未提供个人简介。'), findsOneWidget);
        expect(find.text('当前页面未提供组织资料。'), findsOneWidget);
        expect(find.text('当前页面未提供时长'), findsNothing);
        expect(find.text('当前页面没有可显示的公开模块。'), findsOneWidget);
        expect(find.textContaining('还没有填写'), findsNothing);
        expect(find.textContaining('编辑主页后'), findsNothing);
        expect(find.text('0小时 0分钟'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final (status, text) in [
    ('none', '对方没有加入组织。'),
    ('hidden', '不公开'),
    ('unavailable', '暂时读不到组织资料。'),
  ]) {
    testWidgets('visitor organization slot follows status: $status', (
      tester,
    ) async {
      await tester.pumpWidget(
        support.app(
          PersonalProfileIdentityHeader(
            projection: profile.copyWith(affiliationStatus: status),
            isSelf: false,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(text), findsOneWidget);
      expect(find.text('当前页面未提供组织资料。'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  // CX-PROFILE-HEADER-073-R: offline, the owner's achievements showcase has no
  // local scope and renders nothing, so the column must still say it is empty.
  testWidgets('owner page without achievements scope keeps the guidance', (
    tester,
  ) async {
    await tester.pumpWidget(
      support.app(
        PersonalProfileModuleGrid(
          projection: profile,
          visitorView: false,
          editing: false,
          layout: const [
            PersonalProfileModuleLayoutItem(
              moduleId: 'achievements',
              size: PersonalProfileModuleSize.one,
              isVisible: true,
              position: 0,
            ),
          ],
          onLayoutChanged: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('编辑主页后'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('owner empty page keeps its editing guidance', (tester) async {
    await tester.pumpWidget(
      support.app(
        Column(
          children: [
            PersonalProfileIdentityHeader(projection: profile),
            PersonalProfileModuleGrid(
              projection: profile,
              visitorView: false,
              includeLocalTime: true,
              editing: false,
              layout: const [],
              onLayoutChanged: (_) {},
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('这个人还没有填写个人简介。'), findsOneWidget);
    // User 11-11: playtime moved to the side rail, so an empty column guides
    // the owner again.
    expect(find.text('尚未返回时长'), findsNothing);
    expect(find.textContaining('编辑主页后'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('published visitor introduction is not replaced by empty copy', (
    tester,
  ) async {
    await tester.pumpWidget(
      support.app(
        PersonalProfileIdentityHeader(
          projection: profile.copyWith(about: 'Published introduction'),
          isSelf: false,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Published introduction'), findsOneWidget);
    expect(find.text('当前页面未提供个人简介。'), findsNothing);
  });

  for (final sample in [
    (const Locale('zh', 'TW'), '目前頁面未提供個人簡介。'),
    (const Locale('en'), 'No introduction is available on this page.'),
  ]) {
    testWidgets('visitor empty copy is localized: ${sample.$1}', (
      tester,
    ) async {
      await tester.pumpWidget(
        support.app(
          PersonalProfileIdentityHeader(projection: profile, isSelf: false),
          locale: sample.$1,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(sample.$2), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
