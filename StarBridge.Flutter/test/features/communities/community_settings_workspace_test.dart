import 'dart:io';
import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/design_system/styles/future_restraint_style.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/communities/community_settings_workspace.dart';
import 'package:starbridge_flutter/features/communities/community_profile_dialog.dart';
import 'package:starbridge_flutter/features/communities/community_gameplay_tags.dart';
import 'package:starbridge_flutter/features/communities/community_creation_port.dart';
import 'package:starbridge_flutter/features/communities/community_tag_picker.dart';
import 'package:starbridge_flutter/features/communities/legacy_community_tag_catalog.dart';
import 'package:starbridge_flutter/features/communities/community_roles_dialog.dart';
import 'package:starbridge_flutter/features/communities/example_communities.dart';
import 'package:starbridge_flutter/features/communities/community_workspace_port.dart';
import 'package:starbridge_flutter/features/communities/community_profile_port.dart';
import 'package:starbridge_flutter/features/communities/community_roles_port.dart';
import 'package:starbridge_flutter/features/communities/community_admissions_port.dart';
import 'package:starbridge_flutter/features/communities/community_logs_port.dart';
import 'package:starbridge_flutter/features/communities/community_announcements_port.dart';

import '../friends/social_layout_test.dart' show loadFonts;
import 'community_image_test_support.dart';
import 'community_roles_test.dart' show RolesFake, rolesPayload;
import 'community_management_dialog_test.dart' show ManagementTestPort;
import 'community_admissions_test.dart' show admissionsPayload;
import 'community_navigation_test.dart' show shell;

import 'package:starbridge_flutter/features/communities/communities_module.dart';

const target = '00000000000000000000000000000002';

class SettingsTestPort
    implements
        CommunityWorkspacePort,
        CommunityProfilePort,
        CommunityRolesPort,
        CommunityAdmissionsPort,
        CommunityLogsPort,
        CommunityAnnouncementsPort {
  final example = ExampleCommunities();
  final roles = RolesFake();
  final admissions = ManagementTestPort();
  int profileReads = 0;
  @override
  Stream<void> get invalidations => example.invalidations;
  @override
  bool get rolesAvailable => true;
  @override
  bool get announcementsAvailable => true;
  @override
  bool get logsAvailable => true;
  @override
  bool get logDeletionAvailable => true;
  @override
  Future<CommunityWorkspace> readWorkspace(
    String targetRef,
    String query,
    int offset,
  ) => example.readWorkspace(targetRef, query, offset);
  @override
  Future<Map<String, Object?>> readMedia(
    String targetRef,
    String kind, {
    String? memberRef,
    required int offset,
    String? version,
  }) => example.readMedia(
    targetRef,
    kind,
    memberRef: memberRef,
    offset: offset,
    version: version,
  );
  @override
  Future<CommunityEditingProfile> readProfile({
    String? targetRef,
    String? editRef,
  }) {
    profileReads++;
    return example.readProfile(targetRef: targetRef, editRef: editRef);
  }

  @override
  Future<CommunityProfileOutcome> saveProfile(
    String requestId,
    String editRef,
    Map<String, Object?> changes,
  ) => example.saveProfile(requestId, editRef, changes);
  @override
  Future<CommunityEditingRoles> readRoles({
    String? targetRef,
    String? editRef,
  }) async =>
      CommunityEditingRoles.parse({...rolesPayload(), 'targetRef': target});
  @override
  Future<CommunityProfileOutcome> saveRoles(
    String requestId,
    String editRef,
    List<CommunityRole> values, {
    bool confirmUncertainRetry = false,
  }) => roles.saveRoles(
    requestId,
    editRef,
    values,
    confirmUncertainRetry: confirmUncertainRetry,
  );
  @override
  Future<CommunityAdmissionsPage> readAdmissions(
    String targetRef,
    String section,
    int offset,
  ) async => CommunityAdmissionsPage.parse(
    {...admissionsPayload(), 'targetRef': targetRef},
    targetRef,
    section,
    offset,
  );
  @override
  Future<CommunityAdmissionOutcome> manageAdmissions(
    CommunityAdmissionIntent intent,
  ) => admissions.manageAdmissions(intent);
  @override
  Future<CommunityLogPage> readLogs(
    String targetRef,
    String type,
    String query,
    int offset,
  ) => example.readLogs(targetRef, type, query, offset);
  @override
  Future<CommunityLogOutcome> deleteLog(String targetRef, String logRef) =>
      example.deleteLog(targetRef, logRef);
  @override
  Future<CommunityAnnouncementsPage> readAnnouncements(
    String targetRef, {
    int offset = 0,
    int? expectedRevision,
  }) => example.readAnnouncements(
    targetRef,
    offset: offset,
    expectedRevision: expectedRevision,
  );
  @override
  Future<Map<String, Object?>> readAnnouncementDetail(
    String targetRef,
    String announcementRef,
    int offset,
    String? version,
  ) => example.readAnnouncementDetail(
    targetRef,
    announcementRef,
    offset,
    version,
  );
  Future<void> close() async {
    await example.close();
    await roles.events.close();
    await admissions.changes.close();
  }
}

Future<SettingsTestPort> openSettings(
  WidgetTester tester, {
  Size size = const Size(1040, 550),
  AppearanceMode mode = AppearanceMode.dark,
  Locale locale = const Locale('zh', 'CN'),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final port = SettingsTestPort();
  addTearDown(port.close);
  final workspace = await port.readWorkspace(target, '', 0);
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      supportedLocales: AppStrings.supportedLocales,
      localizationsDelegates: const [
        AppStringsDelegate(),
        ...GlobalMaterialLocalizations.delegates,
      ],
      theme: buildStarBridgeTheme(FutureRestraintStyle.resolve(mode), locale),
      home: Scaffold(
        body: RepaintBoundary(
          key: const ValueKey('settings-capture'),
          child: CommunitySettingsWorkspace(
            port: port,
            workspace: workspace,
            targetRef: target,
            onMembers: () {},
            hasDangerActions: true,
            dangerActions: const Text('Test confirmation entry'),
          ),
        ),
      ),
    ),
  );
  await settleCommunityImages(tester);
  return port;
}

Future<void> select(
  WidgetTester tester,
  String section, {
  bool compact = false,
}) async {
  if (compact) {
    await tester.tap(find.byKey(const ValueKey('settings-category')));
    await tester.pumpAndSettle();
    final context = tester.element(find.byType(CommunitySettingsWorkspace));
    await tester.tap(find.text(communitySettingsText(context, section)).last);
  } else {
    final item = find.byKey(ValueKey('settings-nav-$section'));
    await tester.ensureVisible(item);
    await tester.pump();
    await tester.tap(item);
  }
  await settleCommunityImages(tester);
}

void main() {
  setUpAll(loadFonts);
  testWidgets('desktop profile scrollbar has a gutter outside form controls', (
    tester,
  ) async {
    await openSettings(tester, size: const Size(1280, 720));
    await select(tester, 'discovery');
    final viewport = tester.getRect(
      find.byKey(const ValueKey('profile-continuous-scroll')),
    );
    final control = tester.getRect(find.byType(SwitchListTile).first);
    expect(viewport.right - control.right, greaterThanOrEqualTo(16));
    expect(tester.takeException(), isNull);
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const ValueKey('settings-capture')),
    );
    await tester.runAsync(() async {
      final image = await boundary.toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await File('build/community-profile-scrollbar-gutter.png')
          .writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
    await tester.pumpWidget(const SizedBox());
  }, variant: TargetPlatformVariant({TargetPlatform.windows}));
  for (final compact in [false, true]) {
    testWidgets(
      'profile anchors scroll the same form and rail follows $compact',
      (tester) async {
        final port = await openSettings(
          tester,
          size: compact ? const Size(420, 620) : const Size(1040, 550),
        );
        await select(tester, 'schedule', compact: compact);
        final state = tester.state<CommunityProfileDialogState>(
          find.byType(CommunityProfileDialog),
        );
        final scroll = tester
            .widget<SingleChildScrollView>(
              find.byKey(const ValueKey('profile-continuous-scroll')),
            )
            .controller!;
        for (var i = 0; i < 4; i++) {
          expect(find.byKey(ValueKey('profile-section-$i')), findsOneWidget);
        }
        expect(find.byType(Form), findsOneWidget);
        expect(scroll.offset, greaterThan(0));
        final scheduleOffset = scroll.offset;
        state.model.update('description', '一页中的资料草稿');
        await tester.pump();
        await select(tester, 'contacts', compact: compact);
        expect(scroll.offset, greaterThan(scheduleOffset));
        await select(tester, 'profile', compact: compact);
        expect(scroll.offset, closeTo(0, 1));
        await tester.drag(
          find.byKey(const ValueKey('profile-continuous-scroll')),
          const Offset(0, -220),
        );
        await tester.pumpAndSettle();
        expect(scroll.offset, greaterThan(0));
        // A user scroll, not a rail selection, must update the active chapter.
        scroll.jumpTo(scheduleOffset);
        await tester.pumpAndSettle();
        expect(state.section, 2);
        if (compact) {
          expect(
            tester
                .widget<DropdownButton<String>>(
                  find.byKey(const ValueKey('settings-category')),
                )
                .value,
            'schedule',
          );
        } else {
          expect(
            tester
                .widget<ListTile>(
                  find.byKey(const ValueKey('settings-nav-schedule')),
                )
                .selected,
            isTrue,
          );
        }
        expect(state.model.changes['description'], '一页中的资料草稿');
        expect(port.profileReads, 1);
        expect(find.byType(AlertDialog), findsNothing);
        expect(
          find.widgetWithText(FilledButton, '保存更改').hitTestable(),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
  testWidgets(
    'opening WPF tags selects all five and cancel preserves raw saved format',
    (tester) async {
      await openSettings(tester);
      await select(tester, 'profile');
      final state = tester.state<CommunityProfileDialogState>(
        find.byType(CommunityProfileDialog),
      );
      state.options = const CommunityCreationOptions(
        categories: LegacyCommunityTagCatalog.categories,
        tags: LegacyCommunityTagCatalog.tags,
        timeZones: [],
        defaultTimeZoneId: 'UTC',
        defaultActiveFrom: '18:00',
        defaultActiveTo: '22:00',
        defaultSystem: 'stanton',
        maxTags: 5,
      );
      const raw = 'PVE / 社交 / 休闲 / 佣兵 / 货运';
      state.model.update('type', raw);
      final choosing = state.chooseTags();
      await tester.pumpAndSettle();
      expect(find.byType(CommunityTagPicker), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(InputChip), findsNWidgets(5));
      await tester.tap(find.widgetWithText(TextButton, '取消'));
      await choosing;
      await tester.pumpAndSettle();
      expect(state.model.changes['type'], raw);
      await tester.pumpWidget(const SizedBox());
    },
  );
  test(
    'tag tokenization accepts WPF delimiters and keeps unfamiliar labels',
    () {
      expect(communityTagNames('PVE / 社交; 休闲；佣兵|货运 · 旧自定义、PVE'), [
        'PVE',
        '社交',
        '休闲',
        '佣兵',
        '货运',
        '旧自定义',
      ]);
    },
  );
  for (final mode in [AppearanceMode.dark, AppearanceMode.light]) {
    testWidgets(
      'legacy slash-separated gameplay is displayed as individual tags $mode',
      (tester) async {
        await openSettings(tester, size: const Size(2560, 1392), mode: mode);
        await select(tester, 'profile');
        final state = tester.state<CommunityProfileDialogState>(
          find.byType(CommunityProfileDialog),
        );
        state.model.update('type', 'PVE / 社交 / 休闲 / 佣兵 / 货运');
        await tester.pumpAndSettle();
        for (final name in ['PVE', '社交', '休闲', '佣兵', '货运']) {
          expect(
            find.descendant(
              of: find.byType(CommunityGameplayTags),
              matching: find.text(name),
            ),
            findsOneWidget,
          );
        }
        expect(find.text('PVE / 社交 / 休闲 / 佣兵 / 货运'), findsNothing);
        for (final entry in {
          'PVE': 0xffe08a92,
          '社交': 0xff38b8f2,
          '休闲': 0xffc99cff,
          '佣兵': 0xffe08a92,
          '货运': 0xff8fbdeb,
        }.entries) {
          final badge = tester.widget<Container>(
            find.byKey(ValueKey('community-gameplay-tag-${entry.key}')),
          );
          final decoration = badge.decoration! as BoxDecoration;
          expect(decoration.color, Color(entry.value).withValues(alpha: .14));
          expect(
            (decoration.border! as Border).top.color,
            Color(entry.value).withValues(alpha: .68),
          );
        }
        final branding = tester.getRect(
          find.byKey(const ValueKey('community-profile-branding')),
        );
        final details = tester.getRect(
          find.byKey(const ValueKey('community-profile-details')),
        );
        expect(details.left, branding.left);
        expect(details.top, greaterThanOrEqualTo(branding.bottom));
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const ValueKey('settings-capture')),
        );
        await tester.runAsync(() async {
          final rendered = await boundary.toImage();
          final bytes = await rendered.toByteData(
            format: ui.ImageByteFormat.png,
          );
          await File('build/community-settings-wide-tags-${mode.name}.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          rendered.dispose();
        });
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
  testWidgets('validation selects the category containing the invalid field', (
    tester,
  ) async {
    await openSettings(tester);
    await select(tester, 'profile');
    final state = tester.state<CommunityProfileDialogState>(
      find.byType(CommunityProfileDialog),
    );
    state.model.update('activeSystemIds', <String>[]);
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, '保存更改'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<ListTile>(find.byKey(const ValueKey('settings-nav-schedule')))
          .selected,
      isTrue,
    );
    expect(find.byKey(const ValueKey('profile-section-2')), findsOneWidget);
    expect(state.model.dirty, isTrue);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('wide profile keeps a readable form and a visible save action', (
    tester,
  ) async {
    await openSettings(tester, size: const Size(1920, 1080));
    await select(tester, 'profile');
    expect(
      tester.getSize(find.byType(Form)).width,
      1080,
      reason: 'The continuous form has a readable maximum width.',
    );
    expect(
      tester.getRect(find.byType(Form)).center.dx,
      closeTo(tester.getRect(find.byType(CommunityProfileDialog)).center.dx, 1),
      reason: 'The space on either side of the form must be symmetric.',
    );
    expect(
      find.widgetWithText(FilledButton, '保存更改').hitTestable(),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'profile categories share one draft without a second navigation layer',
    (tester) async {
      await openSettings(tester);
      await select(tester, 'profile');
      final state = tester.state<CommunityProfileDialogState>(
        find.byType(CommunityProfileDialog),
      );
      final profile = state.model.profile;
      final description = find.byWidgetPredicate(
        (w) => w is TextFormField && w.key.toString().contains('-description'),
      );
      await tester.ensureVisible(description);
      await tester.enterText(description, '跨分类保留的草稿');
      await select(tester, 'schedule');
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(ChoiceChip), findsNothing);
      expect(
        tester.state<CommunityProfileDialogState>(
          find.byType(CommunityProfileDialog),
        ),
        same(state),
      );
      expect(
        state.model.profile,
        same(profile),
        reason: 'Moving between fields does not reread the profile.',
      );
      expect(state.model.changes['description'], '跨分类保留的草稿');
      await select(tester, 'contacts');
      expect(find.byType(AlertDialog), findsNothing);
      await select(tester, 'profile');
      expect(find.text('跨分类保留的草稿'), findsOneWidget);
      await select(tester, 'overview');
      expect(
        find.byType(AlertDialog),
        findsOneWidget,
        reason: 'Leaving the entire profile still protects its unsaved draft.',
      );
      await tester.tap(find.widgetWithText(TextButton, '继续编辑'));
      await tester.pumpAndSettle();
      expect(state.model.dirty, isTrue);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('overview actions open the requested editor directly', (
    tester,
  ) async {
    await openSettings(tester);
    await tester.tap(find.byKey(const ValueKey('settings-quick-profile')));
    await tester.pumpAndSettle();
    expect(find.byType(CommunityProfileDialog), findsOneWidget);
    expect(find.byKey(const ValueKey('profile-section-0')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'overview rereads saved profile without reopening the workspace',
    (tester) async {
      await openSettings(tester);
      await select(tester, 'profile');
      final description = find.byWidgetPredicate(
        (w) => w is TextFormField && w.key.toString().contains('-description'),
      );
      await tester.ensureVisible(description);
      await tester.enterText(description, '保存后即时更新的简介');
      await tester.tap(find.widgetWithText(FilledButton, '保存更改'));
      await tester.pumpAndSettle();
      await select(tester, 'overview');
      await tester.scrollUntilVisible(
        find.text('保存后即时更新的简介'),
        120,
        scrollable: find
            .descendant(
              of: find.byType(CommunitySettingsWorkspace),
              matching: find.byType(Scrollable),
            )
            .last,
      );
      expect(find.text('保存后即时更新的简介'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  for (final size in [const Size(1040, 550), const Size(420, 620)]) {
    for (final mode in [AppearanceMode.dark, AppearanceMode.light]) {
      testWidgets('inline settings fit $size $mode without modal editors', (
        tester,
      ) async {
        await openSettings(tester, size: size, mode: mode);
        for (final section in [
          'profile',
          'roles',
          'admissions',
          'logs',
          'announcements',
          'danger',
          'overview',
        ]) {
          await select(tester, section, compact: size.width < 760);
          expect(find.byType(Dialog), findsNothing);
          if (section == 'roles') {
            expect(find.byKey(const ValueKey('role-name')), findsOneWidget);
            expect(
              tester.getTopLeft(find.text('身份组与权限')).dy,
              greaterThanOrEqualTo(0),
            );
          }
          if (section == 'admissions') {
            expect(find.textContaining('Callsign'), findsWidgets);
          }
          expect(tester.takeException(), isNull, reason: section);
          if (size.width > 760 &&
              ['overview', 'profile', 'roles'].contains(section)) {
            final boundary = tester.renderObject<RenderRepaintBoundary>(
              find.byKey(const ValueKey('settings-capture')),
            );
            await tester.runAsync(() async {
              final image = await boundary.toImage();
              final data = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              await File('build/community-settings-$section-${mode.name}.png')
                  .writeAsBytes(data!.buffer.asUint8List());
              image.dispose();
            });
          }
        }
        await tester.pumpWidget(const SizedBox());
      });
    }
  }

  testWidgets('profile drafts survive a cancelled category change', (
    tester,
  ) async {
    await openSettings(tester);
    await select(tester, 'profile');
    final description = find.byWidgetPredicate(
      (w) => w is TextFormField && w.key.toString().contains('-description'),
    );
    await tester.ensureVisible(description);
    await tester.enterText(description, '未保存的简介');
    await select(tester, 'roles');
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.byType(CommunityProfileDialog), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, '继续编辑'));
    await tester.pumpAndSettle();
    expect(find.text('未保存的简介'), findsOneWidget);
    await select(tester, 'roles');
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(TextButton, '放弃更改'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(CommunityRolesDialog), findsOneWidget);
    expect(find.byType(CommunityProfileDialog), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'embedded identity invalidation does not pop the application route',
    (tester) async {
      final port = await openSettings(tester);
      await select(tester, 'profile');
      // The example port exposes the same account-context invalidation contract.
      unawaited(port.example.close());
      await tester.pumpAndSettle();
      expect(find.byType(CommunitySettingsWorkspace), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('role writes block navigation until the result is known', (
    tester,
  ) async {
    final port = await openSettings(tester);
    await select(tester, 'roles');
    await tester.tap(find.byKey(const ValueKey('role-custom_navigation')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('role-name')), '导航组');
    await tester.pumpAndSettle();
    port.roles.pendingSave = Completer<CommunityProfileOutcome>();
    await tester.tap(find.widgetWithText(FilledButton, '保存更改'));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('settings-nav-overview')));
    await tester.pump();
    expect(find.byType(CommunityRolesDialog), findsOneWidget);
    expect(port.roles.writes, 1);
    port.roles.pendingSave!.complete(
      const CommunityProfileOutcome('rejected', error: 'notAllowed'),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('cancelled narrow navigation retains the displayed category', (
    tester,
  ) async {
    await openSettings(tester, size: const Size(420, 620));
    await select(tester, 'profile', compact: true);
    final description = find.byWidgetPredicate(
      (w) => w is TextFormField && w.key.toString().contains('-description'),
    );
    await tester.ensureVisible(description);
    await tester.enterText(description, '保留草稿');
    await select(tester, 'overview', compact: true);
    await tester.tap(find.widgetWithText(TextButton, '继续编辑'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<DropdownButton<String>>(
            find.byKey(const ValueKey('settings-category')),
          )
          .value,
      'profile',
    );
    expect(find.byType(CommunityProfileDialog), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'full 1280 by 720 client preserves management drafts on root navigation',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final module = CommunitiesModule(ExampleCommunities());
      addTearDown(module.dispose);
      await module.refreshJoined();
      module.open(module.joined.last);
      await tester.pumpWidget(
        RepaintBoundary(
          key: const ValueKey('full-settings'),
          child: shell(module),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('community-section-manage')));
      await tester.pumpAndSettle();
      await select(tester, 'profile');
      expect(tester.takeException(), isNull);
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const ValueKey('full-settings')),
      );
      await tester.runAsync(() async {
        final image = await boundary.toImage();
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        await File('build/community-settings-full-client.png')
            .writeAsBytes(data!.buffer.asUint8List());
        image.dispose();
      });
      final description = find.byWidgetPredicate(
        (w) => w is TextFormField && w.key.toString().contains('-description'),
      );
      await tester.ensureVisible(description);
      await tester.enterText(description, '保留完整客户端草稿');
      await tester.tap(find.byKey(const ValueKey('/communities')));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, '继续编辑'));
      await tester.pumpAndSettle();
      expect(module.selected, isNotNull);
      expect(find.text('保留完整客户端草稿'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
