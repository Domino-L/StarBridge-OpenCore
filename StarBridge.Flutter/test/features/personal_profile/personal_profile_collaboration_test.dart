import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/design_system/styles/future_restraint_style.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_models.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_editor.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_schedule_editor.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_collaboration.dart';

import 'local_personal_profile_test.dart' show Harness, edit, shipA;

const schedule = PersonalProfileSchedule(
  timeZoneId: 'America/Regina',
  rhythm: PersonalProfileActivityRhythm.weekends,
  windows: [
    PersonalProfileAvailabilityWindow(
      days: [1, 3],
      startTime: '23:30',
      endTime: '02:15',
    ),
    PersonalProfileAvailabilityWindow(
      days: [0],
      startTime: '08:07',
      endTime: '10:00',
    ),
  ],
);
void main() {
  setUpAll(() async {
    if (const bool.fromEnvironment('PROFILE_COLLAB_GOLDENS')) {
      for (final font in {
        'Source Sans 3': 'assets/fonts/SourceSans3VF-Upright.ttf',
        'Source Han Sans CN': 'assets/fonts/SourceHanSansCN-VF.ttf',
      }.entries) {
        await (FontLoader(
          font.key,
        )..addFont(rootBundle.load(font.value))).load();
      }
    }
  });
  testWidgets(
    'schedule limits, removals, keyboard edits and zone changes retain exact values',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1000, 1100);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      PersonalProfileSchedule? changed;
      final form = GlobalKey<FormState>();
      await tester.pumpWidget(
        _app(
          Padding(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: form,
              child: PersonalProfileScheduleEditor(
                initial: schedule,
                timeZones: const {'America/Regina': 'Regina', 'UTC': 'UTC'},
                enabled: true,
                onChanged: (value) => changed = value,
              ),
            ),
          ),
        ),
      );
      Future<void> tapKey(String key) async {
        await tester.pumpAndSettle();
        final found = find.byKey(Key(key));
        await tester.ensureVisible(found);
        await tester.tap(found);
        await tester.pumpAndSettle();
      }

      await tapKey('profile-schedule-editor');
      await tapKey('profile-add-window');
      expect(changed!.windows.length, 3);
      expect(
        tester
            .widget<OutlinedButton>(find.byKey(const Key('profile-add-window')))
            .onPressed,
        isNull,
      );
      await tapKey('profile-remove-window-0');
      expect(changed!.windows.first.days, [0]);
      expect(
        tester
            .widget<TextFormField>(
              find.byKey(const Key('profile-window-0-start')),
            )
            .initialValue,
        '08:07',
      );
      await tapKey('profile-window-0-day-0');
      expect(form.currentState!.validate(), isFalse);
      await tester.pump();
      await tapKey('profile-window-0-day-2');
      await tapKey('profile-schedule-zone');
      await tester.tap(find.text('UTC').last);
      await tester.pumpAndSettle();
      expect(changed!.timeZoneId, 'UTC');
      expect(changed!.windows.first.startTime, '08:07');
      expect(form.currentState!.validate(), isTrue);
      expect(tester.takeException(), isNull);
      if (const bool.fromEnvironment('PROFILE_COLLAB_GOLDENS')) {
        // Synthetic schedule only; no actual account information or media.
        await tester.pumpAndSettle();
        await expectLater(
          find.byType(Scaffold),
          matchesGoldenFile('../../../build/profile_collaboration_dark.png'),
        );
      }
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  test('local collaboration reopens, preserves other groups and never writes remotely', () async {
    final h = Harness();
    addTearDown(h.close);
    final initial = await h.port.read();
    final minutes = initial.gameplayMinutes;
    expect(initial.local!.timeZones.keys, contains('UTC'));
    await h.port.save(
      edit(
        initial,
        ids: [shipA],
        schedule: schedule,
        playStyle: const PersonalProfilePlayStyle(
          roles: ['pilot'],
          interests: ['exploration'],
          support: ['medical'],
        ),
      ),
    );
    final first = await h.port.read();
    expect(first.roles.single.labelKey, 'profile.legacyRole.pilot');
    expect(first.availabilityWindows.map((w) => w.days), [
      [1, 3],
      [0],
    ]);
    expect(first.timeZoneLabel, 'America/Regina');
    expect(first.gameplayMinutes, minutes);
    expect(first.gameHandle, initial.gameHandle);
    final originalSchedule = h.connection.content!['schedule'];
    await h.port.save(
      edit(first, playStyle: const PersonalProfilePlayStyle(roles: ['medic'])),
    );
    expect(h.connection.content!['playStyle'], {
      'roles': ['medic'],
      'interests': ['exploration'],
      'support': ['medical'],
    });
    expect(h.connection.content!['schedule'], originalSchedule);
    expect(h.connection.content!['favoriteShipIds'], [shipA]);
    h.remote.available = false;
    final offline = await h.port.read();
    expect(offline.roles.single.labelKey, 'profile.legacyRole.medic');
    expect(offline.availabilityWindows.first.endTime, '02:15');
    await h.port.save(
      edit(
        offline,
        schedule: const PersonalProfileSchedule(
          timeZoneId: '',
          rhythm: PersonalProfileActivityRhythm.irregular,
          windows: [],
        ),
        playStyle: const PersonalProfilePlayStyle(roles: []),
      ),
    );
    final cleared = await h.port.read();
    expect(cleared.roles, isEmpty);
    expect(cleared.availabilityWindows, isEmpty);
    expect(cleared.activityRhythm, PersonalProfileActivityRhythm.irregular);
    expect(h.remote.writes, 0);
  });
  test('absent fields remain absent on an unrelated edit; summaries retain exact days', () async {
    final h = Harness();
    addTearDown(h.close);
    await h.port.save(edit(await h.port.read()));
    expect(h.connection.content!.containsKey('schedule'), isFalse);
    expect(h.connection.content!.containsKey('playStyle'), isFalse);
    final strings = AppStrings.resolve(const Locale('zh', 'CN'));
    expect(ProfileCollaboration.daysLabel(strings, [1, 3]), '周一 / 周三');
    expect(ProfileCollaboration.daysLabel(strings, [1, 2, 3, 4, 5]), '工作日');
    expect(ProfileCollaboration.validTime('24:00'), isFalse);
    expect(ProfileCollaboration.validTime('08:07'), isTrue);
    expect(ProfileCollaboration.validSchedule(schedule), isTrue);
    for (final locale in AppStrings.supportedLocales) {
      final strings = AppStrings.resolve(locale);
      for (final group in ProfileCollaboration.options.values) {
        for (final option in group.values) {
          expect(strings.text(option.labelKey), isNot(option.labelKey));
        }
      }
    }
  });
  testWidgets(
    'editor keeps failed drafts, enforces time validation, and preserves identity fields',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1000, 1000);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final h = Harness();
      addTearDown(h.close);
      late PersonalProfileSnapshot snapshot;
      await tester.runAsync(() async {
        await h.port.save(edit(await h.port.read(), schedule: schedule));
        snapshot = await h.port.read();
      });
      final projection = PersonalProfileProjection.fromSnapshot(snapshot);
      PersonalProfileEdit? submitted;
      var attempts = 0;
      await tester.pumpWidget(
        _app(
          PersonalProfileEditorPanel(
            projection: projection,
            moduleLayout: projection.moduleLayout,
            onCancel: () {},
            onSaved: () {},
            onWallpaperChanged: (_) {},
            onSave: (edit) async {
              attempts++;
              submitted = edit;
              return const PersonalProfileActionResult(
                PersonalProfileActionOutcome.failed,
              );
            },
          ),
        ),
      );
      Future<void> tapKey(String key) async {
        await tester.pumpAndSettle();
        final found = find.byKey(Key(key));
        expect(found, findsOneWidget, reason: key);
        await tester.ensureVisible(found);
        await tester.tap(found);
        await tester.pumpAndSettle();
      }

      await tapKey('profile-roles-editor');
      await tapKey('profile-roles-medic');
      expect(
        tester
            .widget<FilterChip>(find.byKey(const Key('profile-roles-scout')))
            .onSelected,
        isNull,
      );
      await tapKey('profile-schedule-editor');
      final start = find.byKey(const Key('profile-window-0-start'));
      await tester.ensureVisible(start);
      await tester.enterText(start, '24:00');
      await tester.pump();
      // Collapsed invalid fields must still block saving and show a visible explanation.
      await tapKey('profile-schedule-editor');
      await tapKey('profile-save');
      expect(attempts, 0);
      expect(find.byKey(const Key('profile-validation-error')), findsOneWidget);
      await tapKey('profile-schedule-editor');
      await tester.ensureVisible(start);
      await tester.enterText(start, '21:07');
      await tester.pump();
      await tapKey('profile-save');
      expect(attempts, 1);
      expect(submitted!.schedule!.windows.first.startTime, '21:07');
      expect(submitted!.schedule!.windows.first.days, [1, 3]);
      expect(submitted!.playStyle!.roles, contains('medic'));
      expect(submitted!.schedule!.timeZoneId, 'America/Regina');
      await tapKey('profile-save');
      expect(attempts, 2);
      expect(submitted!.schedule!.windows.first.startTime, '21:07');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  for (final locale in AppStrings.supportedLocales) {
    for (final mode in AppearanceMode.values) {
      testWidgets(
        'expanded controls fit $locale $mode at 360px with large text',
        (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = const Size(360, 1100);
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.view.resetPhysicalSize);
          final h = Harness();
          addTearDown(h.close);
          late PersonalProfileSnapshot snapshot;
          await tester.runAsync(() async {
            await h.port.save(
              edit(
                await h.port.read(),
                schedule: schedule,
                playStyle: const PersonalProfilePlayStyle(
                  roles: [],
                  interests: [],
                  support: [],
                ),
              ),
            );
            snapshot = await h.port.read();
          });
          final projection = PersonalProfileProjection.fromSnapshot(snapshot);
          await tester.pumpWidget(
            _app(
              PersonalProfileEditorPanel(
                projection: projection,
                moduleLayout: projection.moduleLayout,
                onCancel: () {},
                onSaved: () {},
                onWallpaperChanged: (_) {},
                onSave: (_) async => const PersonalProfileActionResult(
                  PersonalProfileActionOutcome.failed,
                ),
              ),
              locale: locale,
              mode: mode,
              scale: 1.5,
            ),
          );
          for (final key in [
            'profile-roles-editor',
            'profile-interests-editor',
            'profile-support-editor',
            'profile-schedule-editor',
          ]) {
            await tester.pumpAndSettle();
            final found = find.byKey(Key(key));
            expect(found, findsOneWidget, reason: key);
            await tester.ensureVisible(found);
            await tester.tap(found);
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
          }
          expect(find.textContaining('profile.collab.'), findsNothing);
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );
    }
  }
}

Widget _app(
  Widget child, {
  Locale locale = const Locale('zh', 'CN'),
  AppearanceMode mode = AppearanceMode.dark,
  double scale = 1,
}) => MaterialApp(
  locale: locale,
  supportedLocales: AppStrings.supportedLocales,
  localizationsDelegates: const [
    AppStringsDelegate(),
    ...GlobalMaterialLocalizations.delegates,
  ],
  theme: buildStarBridgeTheme(
    FutureRestraintStyle.resolve(mode).withReducedMotion(true),
    locale,
  ),
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
    child: child!,
  ),
  home: Scaffold(body: SingleChildScrollView(child: child)),
);
