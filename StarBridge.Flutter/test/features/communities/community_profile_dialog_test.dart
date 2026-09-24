import 'community_image_test_support.dart';

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/design_system/styles/future_restraint_style.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/communities/community_profile_dialog.dart';
import 'package:starbridge_flutter/features/communities/community_profile_port.dart';
import 'package:starbridge_flutter/features/communities/community_profile_copy.dart';
import 'package:starbridge_flutter/features/communities/community_workspace_view.dart';
import 'package:starbridge_flutter/features/communities/community_workspace_port.dart';

import 'community_workspace_test.dart' show workspacePayload, mediaChunk;

import 'community_profile_test.dart' show profilePayload;
import 'community_creation_dialog_test.dart' show FormPort;
import '../friends/social_layout_test.dart' show loadFonts;

class EditorPort extends FormPort implements CommunityProfilePort {
  final profile = profilePayload();
  final saves = <Map<String, Object?>>[];
  CommunityProfileOutcome saveResult = const CommunityProfileOutcome(
    'accepted',
    revision: 8,
  );
  @override
  Future<CommunityEditingProfile> readProfile({
    String? targetRef,
    String? editRef,
  }) async => CommunityEditingProfile.parse(profile);
  @override
  Future<CommunityProfileOutcome> saveProfile(
    String requestId,
    String editRef,
    Map<String, Object?> values,
  ) async {
    saves.add(values);
    if (saveResult.status == 'accepted') {
      if (values.containsKey('name')) profile['name'] = values['name'];
      profile['profile'] = <String, Object?>{
        ...Map<String, Object?>.from(profile['profile'] as Map),
        ...Map<String, Object?>.from(jsonDecode(jsonEncode(values)) as Map),
      };
      profile['profileRevision'] = saveResult.revision;
    }
    return saveResult;
  }
}

class WorkspaceEditorPort extends EditorPort implements CommunityWorkspacePort {
  int workspaceReads = 0, mediaReads = 0;
  @override
  Future<CommunityWorkspace> readWorkspace(
    String targetRef,
    String query,
    int offset,
  ) async {
    workspaceReads++;
    final value = workspacePayload(target: targetRef, query: query)
      ..['code'] = 'A';
    value['access'] = {
      'isOwner': false,
      'canEditProfile': false,
      'canEditLogo': true,
      'canEditBanner': false,
      'canReviewApplications': false,
      'canRemoveMembers': false,
      'canCreateInvite': false,
      'canManageAnnouncements': false,
    };
    return CommunityWorkspace.parse(value);
  }

  @override
  Future<Map<String, Object?>> readMedia(
    String targetRef,
    String kind, {
    String? memberRef,
    required int offset,
    String? version,
  }) async {
    mediaReads++;
    return mediaChunk(
      base64Decode(FormPort.image.split(',').last),
      offset,
      kind: kind,
      memberRef: memberRef,
    );
  }
}

Future<void> open(
  WidgetTester tester,
  EditorPort port, {
  Locale locale = const Locale('zh', 'CN'),
  double width = 1100,
  void Function(String code, String name)? onNameConfirmed,
}) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(port.changes.close);
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      supportedLocales: AppStrings.supportedLocales,
      localizationsDelegates: const [
        AppStringsDelegate(),
        ...GlobalMaterialLocalizations.delegates,
      ],
      theme: buildStarBridgeTheme(
        FutureRestraintStyle.resolve(AppearanceMode.dark),
        locale,
      ),
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            child: const Text('Open editor'),
            onPressed: () {
              showDialog<bool>(
                context: context,
                barrierDismissible: false,
                builder: (_) => RepaintBoundary(
                  key: const ValueKey('profile-capture'),
                  child: CommunityProfileDialog(
                    port: port,
                    onNameConfirmed: onNameConfirmed,
                    targetRef: 'a' * 32,
                  ),
                ),
              );
            },
          ),
        ),
      ),
    ),
  );
  await settleCommunityImages(tester);
  await tester.tap(find.text('Open editor'));
  await settleCommunityImages(tester);
}

String text(WidgetTester tester, String key) =>
    profileText(tester.element(find.byType(CommunityProfileDialog)), key);
Future<void> tab(WidgetTester tester, String key) async {
  await tester.tap(find.widgetWithText(ChoiceChip, text(tester, key)));
  await settleCommunityImages(tester);
}

Future<void> enter(WidgetTester tester, String field, String value) async {
  final found = find.byWidgetPredicate(
    (w) => w is TextFormField && w.key.toString().contains('-$field'),
  );
  await tester.ensureVisible(found);
  await tester.enterText(found, value);
  await settleCommunityImages(tester);
}

Future<void> save(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(FilledButton, text(tester, 'save')));
  await settleCommunityImages(tester);
}

void main() {
  setUpAll(loadFonts);
  testWidgets(
    'Logo-only member has a formal editor entry and unchanged close does not refresh',
    (tester) async {
      final port = WorkspaceEditorPort();
      port.profile['access'] = {
        'canEditProfile': false,
        'canEditLogo': true,
        'canEditBanner': false,
      };
      await open(tester, port);
      await tester.tap(find.byTooltip(text(tester, 'close')));
      await settleCommunityImages(tester);
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'CN'),
          supportedLocales: AppStrings.supportedLocales,
          localizationsDelegates: const [
            AppStringsDelegate(),
            ...GlobalMaterialLocalizations.delegates,
          ],
          theme: buildStarBridgeTheme(
            FutureRestraintStyle.resolve(AppearanceMode.dark),
            const Locale('zh', 'CN'),
          ),
          home: Scaffold(
            body: CommunityWorkspaceView(port: port, targetRef: 'a' * 32),
          ),
        ),
      );
      await settleCommunityImages(tester);
      await tester.tap(find.byKey(const ValueKey('community-section-manage')));
      await settleCommunityImages(tester);
      await tester.tap(find.byKey(const ValueKey('settings-nav-profile')));
      await settleCommunityImages(tester);
      expect(find.byType(CommunityProfileDialog), findsOneWidget);
      final description = find.byWidgetPredicate(
        (w) => w is TextFormField && w.key.toString().contains('-description'),
      );
      expect(tester.widget<TextFormField>(description).enabled, isFalse);
      final before = port.workspaceReads;
      await tester.tap(find.byKey(const ValueKey('community-settings-back')));
      await settleCommunityImages(tester);
      expect(port.workspaceReads, before);
      expect(port.saves, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'Logo selection uses Native crop and saves only on explicit save',
    (tester) async {
      final port = EditorPort();
      await open(tester, port);
      await tester.tap(
        find.widgetWithText(OutlinedButton, text(tester, 'pickLogo')),
      );
      await settleCommunityImages(tester);
      await tester.tap(
        find.widgetWithText(FilledButton, text(tester, 'useImage')),
      );
      await settleCommunityImages(tester);
      expect(port.saves, isEmpty);
      expect(port.picks, 1);
      expect(port.crops, 1);
      expect(port.clears, 1);
      await save(tester);
      expect(port.saves.single['logoImageData'], FormPort.image);
      expect(port.saves.single.containsKey('clearLogoImage'), isFalse);
      await tester.pumpWidget(const SizedBox());
    },
  );
  for (final locale in const [
    Locale('zh', 'CN'),
    Locale('zh', 'TW'),
    Locale('en', 'US'),
  ]) {
    for (final width in [760.0, 1100.0]) {
      testWidgets(
        'Profile sections, scoped save and WPF values $locale $width',
        (tester) async {
          final port = EditorPort();
          await open(tester, port, locale: locale, width: width);
          for (final section in [
            'discovery',
            'schedule',
            'contacts',
            'basic',
          ]) {
            await tab(tester, section);
            expect(tester.takeException(), isNull);
          }
          await enter(tester, 'description', 'Changed description');
          await save(tester);
          expect(port.saves.single, {'description': 'Changed description'});
          expect(find.text(text(tester, 'saved')), findsOneWidget);
          expect((port.profile['profile'] as Map)['language'], 'English');
          expect(
            (port.profile['profile'] as Map)['publicShowExternalContacts'],
            isFalse,
          );
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        },
      );
    }
  }
  testWidgets(
    'Close offers keep editing, discard and save without silent draft loss',
    (tester) async {
      final port = EditorPort();
      await open(tester, port);
      await enter(tester, 'description', 'Unsaved');
      await tester.tap(find.byTooltip(text(tester, 'close')));
      await settleCommunityImages(tester);
      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.tap(
        find.widgetWithText(TextButton, text(tester, 'continue')),
      );
      await settleCommunityImages(tester);
      expect(find.text('Unsaved'), findsOneWidget);
      expect(port.saves, isEmpty);
      await tester.tap(find.byTooltip(text(tester, 'close')));
      await settleCommunityImages(tester);
      await tester.tap(
        find.widgetWithText(TextButton, text(tester, 'discard')).last,
      );
      await settleCommunityImages(tester);
      expect(find.byType(CommunityProfileDialog), findsNothing);
      expect(port.saves, isEmpty);
    },
  );
  testWidgets(
    'Private contacts require explicit confirmation and nested dialogs close on account change',
    (tester) async {
      final port = EditorPort();
      await open(tester, port);
      await tab(tester, 'contacts');
      final publish = find.widgetWithText(
        TextButton,
        text(tester, 'publishContacts'),
      );
      await tester.ensureVisible(publish);
      await tester.tap(publish);
      await settleCommunityImages(tester);
      expect(port.saves, isEmpty);
      await tester.tap(
        find.widgetWithText(TextButton, text(tester, 'continue')),
      );
      await settleCommunityImages(tester);
      expect(
        (port.profile['profile'] as Map)['publicShowExternalContacts'],
        isFalse,
      );
      await tester.tap(publish);
      await settleCommunityImages(tester);
      await tester.tap(
        find.widgetWithText(FilledButton, text(tester, 'publishContacts')),
      );
      await settleCommunityImages(tester);
      await save(tester);
      expect(port.saves.single, {'publicShowExternalContacts': true});
      await enter(tester, 'websiteUrl', 'https://example.invalid');
      await tester.tap(find.byTooltip(text(tester, 'close')));
      await settleCommunityImages(tester);
      port.changes.add(null);
      await settleCommunityImages(tester);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(CommunityProfileDialog), findsNothing);
    },
  );
  testWidgets('Uncertain saves retain input and disable duplicate submission', (
    tester,
  ) async {
    final port = EditorPort()
      ..saveResult = const CommunityProfileOutcome(
        'unknown',
        error: 'outcomeUnknown',
      );
    await open(tester, port);
    await enter(tester, 'description', 'Keep draft');
    await save(tester);
    expect(port.saves, hasLength(1));
    expect(find.text('Keep draft'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, text(tester, 'save')),
          )
          .onPressed,
      isNull,
    );
    expect(find.text(text(tester, 'outcomeUnknown')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('Activity windows keep weekdays and overnight fields in save', (
    tester,
  ) async {
    final port = EditorPort();
    await open(tester, port);
    await tab(tester, 'schedule');
    final end = find.byWidgetPredicate(
      (w) =>
          w is DropdownButtonFormField<String> &&
          w.key.toString().contains('-endTime-0'),
    );
    await tester.ensureVisible(end);
    await tester.tap(end);
    await tester.pumpAndSettle();
    await tester.tap(find.text('03').last);
    await settleCommunityImages(tester);
    await save(tester);
    expect(port.saves.single['activityWindows'], [
      {
        'days': ['fri'],
        'startTime': '22:00',
        'endTime': '03:00',
        'endsNextDay': true,
      },
    ]);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('Render real profile form without starting visible client', (
    tester,
  ) async {
    final port = EditorPort();
    await open(tester, port);
    await tab(tester, 'contacts');
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const ValueKey('profile-capture')),
    );
    final notificationLabel = tester.widget<Text>(
      find.text(text(tester, 'emailNotificationsEnabled')),
    );
    expect(
      notificationLabel.style?.fontFamilyFallback,
      contains('Source Han Sans CN'),
    );
    await tester.runAsync(() async {
      final image = await boundary.toImage();
      final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!;
      final file = File('build/community-profile-ui-review.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes.buffer.asUint8List());
      image.dispose();
    });
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
