import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/features/gameplay_time/gameplay_time_panel.dart';
import 'package:starbridge_flutter/features/personal_profile/in_memory_personal_profile_adapter.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_module.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_page.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_summary.dart';

import 'gameplay_time_test.dart' as support;
import '../personal_profile/local_personal_profile_test.dart' as local;

Future<void> prepare(WidgetTester tester, support.Harness h) async {
  final task = h.controller.importHistory(() async => 'C:/synthetic/Game.log');
  await tester.pump();
  await task;
}

void main() {
  const renderGoldens = bool.fromEnvironment('GAMEPLAY_GOLDENS');
  setUpAll(() async {
    if (!renderGoldens) return;
    for (final font in {
      'Source Sans 3': 'assets/fonts/SourceSans3VF-Upright.ttf',
      'Source Han Sans CN': 'assets/fonts/SourceHanSansCN-VF.ttf',
    }.entries) {
      await (FontLoader(font.key)..addFont(rootBundle.load(font.value))).load();
    }
  });
  for (final width in [360.0, 1100.0]) {
    testWidgets('synthetic gameplay settings visual $width', (tester) async {
      final h = support.Harness()..seconds = 9030;
      await tester.pump();
      await tester.binding.setSurfaceSize(Size(width, 1000));
      await tester.pumpWidget(
        support.app(
          RepaintBoundary(
            key: const Key('gameplay-visual'),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: GameplayTimePanel(controller: h.controller),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await expectLater(
        find.byKey(const Key('gameplay-visual')),
        matchesGoldenFile('goldens/gameplay-settings-${width.toInt()}.png'),
      );
      await tester.pumpWidget(const SizedBox());
      await h.close(tester);
      await tester.binding.setSurfaceSize(null);
    }, skip: !renderGoldens);
  }
  testWidgets(
    'stats failure clears recording observation but retains saved values and off',
    (tester) async {
      final h = support.Harness(showOnProfile: false)..seconds = 600;
      await tester.pump();
      expect(h.controller.value.recording, isTrue);
      h.wrongOwner = true;
      await tester.pump(const Duration(seconds: 5));
      expect(h.controller.value.recording, isFalse);
      expect(h.controller.value.gameState, 'unknown');
      expect(h.controller.value.seconds, 600);
      expect(h.controller.value.showOnProfile, isFalse);
      h.wrongOwner = false;
      await tester.pump(const Duration(seconds: 5));
      expect(h.controller.value.showOnProfile, isFalse);
      expect(h.requests.where((r) => r.name.contains('set')), isEmpty);
      await h.close(tester);
    },
  );

  for (final phase in ['preview', 'confirm']) {
    testWidgets('recordingRequired at $phase never reenables recording', (
      tester,
    ) async {
      final h = support.Harness(consent: 'declined');
      await tester.pump();
      if (phase == 'preview') h.previewResult = 'recordingRequired';
      await prepare(tester, h);
      if (phase == 'confirm') {
        h.confirmResult = 'recordingRequired';
        final task = h.controller.confirmHistory(h.controller.value.preview!);
        await tester.pump();
        await task;
      }
      expect(h.controller.value.historyError, 'recordingRequired');
      expect(h.controller.value.preview, isNull);
      expect(h.controller.value.historyState, 'available');
      expect(h.controller.value.consent, 'declined');
      expect(h.requests.where((r) => r.name.endsWith('setConsent')), isEmpty);
      await tester.pumpWidget(
        support.app(GameplayTimePanel(controller: h.controller)),
      );
      await tester.pumpAndSettle();
      expect(find.text('请先开启游戏时长记录，再补录历史时长。'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await h.close(tester);
    });
  }

  for (final request in ['historyStatus', 'historyPreview']) {
    testWidgets(
      '$request uses 65 seconds and account switch drops late response',
      (tester) async {
        final h = support.Harness();
        await tester.pump();
        h.holdNames.add('gameplayTime.$request');
        final task = h.controller.importHistory(
          () async => 'C:/synthetic/Game.log',
        );
        await tester.pump();
        await tester.pump(const Duration(seconds: 64));
        expect(h.controller.value.busy, isTrue);
        final old = h.held!;
        h.changeAccount();
        h.holdNames.clear();
        h.respond(old);
        await tester.pump();
        await task;
        expect(h.controller.value.preview, isNull);
        expect(h.controller.value.historyState, 'unchecked');
        expect(h.controller.value.busy, isFalse);
        await h.close(tester);
      },
    );
  }

  testWidgets(
    'explicit off persists; missing old fields default without writes',
    (tester) async {
      final h = support.Harness(consent: 'declined', showOnProfile: false);
      await tester.pump();
      expect(h.controller.value.consent, 'declined');
      expect(h.controller.value.showOnProfile, isFalse);
      expect(h.requests.map((r) => r.name), [
        'account.getCurrent',
        'gameplayTime.read',
      ]);
      final change = h.controller.setVisibility(true);
      await tester.pump();
      await change;
      expect(h.requests.last.payload, {
        'schemaVersion': 1,
        'showOnProfile': true,
      });
      expect(h.controller.value.consent, 'declined');
      expect(h.controller.value.showOnProfile, isTrue);
      await h.close(tester);
      final old = support.Harness(historySupported: false, oldProjection: true);
      await tester.pump();
      expect(old.controller.value.showOnProfile, isTrue);
      expect(old.controller.value.historicalSeconds, 0);
      await tester.pumpWidget(
        support.app(GameplayTimePanel(controller: old.controller)),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('gameplay-time-profile-switch')),
        findsNothing,
      );
      expect(find.byKey(const Key('gameplay-history-import')), findsNothing);
      await old.controller.importHistory(
        () async => throw StateError('must not pick'),
      );
      expect(old.requests.where((r) => r.name.contains('history')), isEmpty);
      await tester.pumpWidget(const SizedBox());
      await old.close(tester);
    },
  );

  testWidgets(
    'visibility lost reply requires explicit retry and preserves totals',
    (tester) async {
      final h = support.Harness()..seconds = 3600;
      await tester.pump();
      h.holdNames.add('gameplayTime.setVisibility');
      final write = h.controller.setVisibility(false);
      await tester.pump();
      await tester.pump(const Duration(seconds: 10));
      await write;
      expect(h.controller.value.showOnProfile, isTrue);
      expect(h.controller.value.error, 'visibilityUnconfirmed');
      await tester.pump(const Duration(seconds: 5));
      expect(
        h.requests.where((r) => r.name.endsWith('setVisibility')).length,
        1,
      );
      h.holdNames.clear();
      final retry = h.controller.retry();
      await tester.pump();
      await retry;
      expect(h.controller.value.showOnProfile, isFalse);
      expect(h.controller.value.seconds, 3600);
      await h.close(tester);
    },
  );

  for (final state in [
    'imported',
    'unchecked',
    'identityRequired',
    'overlapUnknown',
    'unavailable',
    'busy',
  ]) {
    testWidgets('status $state blocks file selection', (tester) async {
      final h = support.Harness()..statusResult = state;
      await tester.pump();
      var selected = false;
      final task = h.controller.importHistory(() async {
        selected = true;
        return null;
      });
      await tester.pump();
      await task;
      expect(selected, isFalse);
      expect(h.controller.value.preview, isNull);
      expect(
        h.requests.where((r) => r.name == 'gameplayTime.historyConfirm'),
        isEmpty,
      );
      await h.close(tester);
    });
  }

  testWidgets(
    'picker cancel, picker failure and preview cancel preserve eligibility',
    (tester) async {
      final h = support.Harness();
      await tester.pump();
      final cancel = h.controller.importHistory(() async => null);
      await tester.pump();
      await cancel;
      expect(h.controller.value.historyState, 'available');
      expect(
        h.requests.where((r) => r.name == 'gameplayTime.historyPreview'),
        isEmpty,
      );
      final fail = h.controller.importHistory(
        () async => throw StateError('synthetic failure'),
      );
      await tester.pump();
      await fail;
      expect(h.controller.value.historyError, 'unavailable');
      await prepare(tester, h);
      expect(h.controller.value.preview!.seconds, 5400);
      h.controller.cancelPreview(h.controller.value.preview!);
      expect(h.controller.value.preview, isNull);
      expect(h.controller.value.historyState, 'available');
      expect(
        h.requests.where((r) => r.name == 'gameplayTime.historyConfirm'),
        isEmpty,
      );
      await prepare(tester, h);
      final confirm = h.controller.confirmHistory(h.controller.value.preview!);
      await tester.pump();
      await confirm;
      expect(h.controller.value.historyState, 'imported');
      expect(h.controller.value.historicalSeconds, 5400);
      expect(h.controller.value.seconds, 0);
      final count = h.requests.length;
      await h.controller.importHistory(
        () async => throw StateError('already imported'),
      );
      expect(h.requests.length, count);
      await h.close(tester);
    },
  );

  testWidgets(
    'confirmation waits 65 seconds and retries the identical preview once',
    (tester) async {
      final h = support.Harness();
      await tester.pump();
      await prepare(tester, h);
      final preview = h.controller.value.preview!;
      h.holdNames.add('gameplayTime.historyConfirm');
      final pending = h.controller.confirmHistory(preview);
      await tester.pump();
      await tester.pump(const Duration(seconds: 64));
      expect(h.controller.value.busy, isTrue);
      await h.controller.confirmHistory(preview);
      await tester.pump(const Duration(seconds: 1));
      await pending;
      expect(h.controller.value.historyError, 'confirmUncertain');
      expect(identical(h.controller.value.preview, preview), isTrue);
      await tester.pump(const Duration(seconds: 10));
      expect(
        h.requests.where((r) => r.name.endsWith('historyConfirm')).length,
        1,
      );
      h.holdNames.clear();
      final retry = h.controller.confirmHistory(preview);
      await tester.pump();
      await retry;
      final confirms = h.requests.where(
        (r) => r.name.endsWith('historyConfirm'),
      );
      expect(confirms.map((r) => r.payload['previewId']), [
        preview.id,
        preview.id,
      ]);
      expect(h.controller.value.historyState, 'imported');
      await h.close(tester);
    },
  );

  for (final state in [
    'empty',
    'path',
    'limit',
    'previewExpired',
    'accountChanged',
    'cancelled',
  ]) {
    testWidgets('preview result $state is retryable without consuming import', (
      tester,
    ) async {
      final h = support.Harness()..previewResult = state;
      await tester.pump();
      await prepare(tester, h);
      expect(h.controller.value.historyError, state);
      expect(h.controller.value.preview, isNull);
      expect(h.controller.value.historyState, 'available');
      h.previewResult = 'preview';
      await prepare(tester, h);
      expect(h.controller.value.preview, isNotNull);
      await h.close(tester);
    });
  }

  for (final part in ['environment', 'authority', 'subject']) {
    testWidgets('history rejects wrong $part', (tester) async {
      final h = support.Harness();
      await tester.pump();
      if (part == 'subject') {
        h.wrongOwner = true;
      } else {
        h.wrongContext[part] = 'other';
      }
      await prepare(tester, h);
      expect(h.controller.value.historyError, 'unavailable');
      expect(h.controller.value.preview, isNull);
      await h.close(tester);
    });
  }

  testWidgets('account switch discards a pending native picker result', (
    tester,
  ) async {
    final h = support.Harness();
    await tester.pump();
    final picker = Completer<String?>();
    final task = h.controller.importHistory(() => picker.future);
    await tester.pump();
    expect(h.controller.value.operation, 'choosing');
    h.changeAccount();
    await tester.pump();
    picker.complete('C:/synthetic/Game.log');
    await tester.pump();
    await task;
    expect(h.controller.value.preview, isNull);
    expect(
      h.requests.where((r) => r.name == 'gameplayTime.historyPreview'),
      isEmpty,
    );
    expect(h.controller.value.busy, isFalse);
    await h.close(tester);
  });

  for (final locale in AppStrings.supportedLocales) {
    for (final width in [360.0, 1100.0]) {
      testWidgets(
        'preview fits $locale/$width; cancel and account switch dismiss',
        (tester) async {
          final h = support.Harness();
          await tester.pump();
          await tester.binding.setSurfaceSize(Size(width, 900));
          await tester.pumpWidget(
            support.app(
              MediaQuery(
                data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
                child: GameplayTimePanel(
                  controller: h.controller,
                  pickLog: () async => 'C:/synthetic/Game.log',
                ),
              ),
              locale: locale,
            ),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const Key('gameplay-history-import')));
          await tester.pumpAndSettle();
          expect(
            find.byKey(const Key('gameplay-history-preview')),
            findsOneWidget,
          );
          expect(
            find.byKey(const Key('gameplay-history-preview-duration')),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
          await tester.tap(find.byKey(const Key('gameplay-history-cancel')));
          await tester.pumpAndSettle();
          expect(h.controller.value.preview, isNull);
          await tester.tap(find.byKey(const Key('gameplay-history-import')));
          await tester.pumpAndSettle();
          final old = h.controller.value.preview!;
          h.changeAccount();
          await tester.pumpAndSettle();
          expect(
            find.byKey(const Key('gameplay-history-preview')),
            findsNothing,
          );
          await h.controller.confirmHistory(old);
          expect(
            h.requests.where((r) => r.name == 'gameplayTime.historyConfirm'),
            isEmpty,
          );
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
          await h.close(tester);
          await tester.binding.setSurfaceSize(null);
        },
      );
    }
  }

  testWidgets(
    'profile keeps remote history alongside local detail; visibility hides metric',
    (tester) async {
      final h = support.Harness()..seconds = 3600;
      final profile = createPersonalProfileModule(
        InMemoryPersonalProfileAdapter.forReview(signedIn: true),
      );
      await profile.initialize();
      await tester.pump();
      final minutes = profile.projection.value.gameplayMinutes;
      await tester.pumpWidget(
        support.app(
          PersonalProfileSummaryStrip(
            projection: profile.projection.value,
            gameplayTime: h.controller,
          ),
          locale: const Locale('en'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Existing historical playtime'), findsOneWidget);
      expect(
        find.text('${minutes ~/ 60} h ${minutes % 60} min'),
        findsOneWidget,
      );
      expect(find.text('Total on this PC: 1 h 0 min'), findsOneWidget);
      expect(profile.projection.value.gameplayMinutes, minutes);
      expect(find.byType(Switch), findsNothing);
      final hide = h.controller.setVisibility(false);
      await tester.pump();
      await hide;
      await tester.pumpAndSettle();
      expect(find.text('Existing historical playtime'), findsNothing);
      expect(profile.projection.value.gameplayMinutes, minutes);
      await tester.pumpWidget(const SizedBox());
      profile.dispose();
      await h.close(tester);
    },
  );

  for (final locale in AppStrings.supportedLocales) {
    for (final width in [360.0, 1100.0]) {
      testWidgets(
        'remote unavailable profile retains readonly local metric $locale/$width',
        (tester) async {
          final h = support.Harness()..seconds = 3600;
          final saved = local.Harness()..remote.available = false;
          final profile = createPersonalProfileModule(saved.port);
          await tester.runAsync(profile.initialize);
          await tester.pump();
          await tester.binding.setSurfaceSize(Size(width, 950));
          await tester.pumpWidget(
            support.app(
              SizedBox(
                height: 900,
                child: PersonalProfilePage(
                  module: profile,
                  gameplayTime: h.controller,
                ),
              ),
              locale: locale,
            ),
          );
          await tester.pumpAndSettle();
          final strings = AppStrings.resolve(locale);
          expect(
            find.byKey(const Key('profile-local-remote-unavailable')),
            findsOneWidget,
          );
          expect(
            find.textContaining(strings.text('gameplay.localTotal')),
            findsOneWidget,
          );
          expect(
            find.descendant(
              of: find.byType(PersonalProfileSummaryStrip),
              matching: find.text('—'),
            ),
            findsOneWidget,
          );
          expect(find.byKey(const Key('gameplay-time-panel')), findsNothing);
          expect(tester.takeException(), isNull);
          final hide = h.controller.setVisibility(false);
          await tester.pump();
          await hide;
          await tester.pumpAndSettle();
          expect(
            find.textContaining(strings.text('gameplay.localTotal')),
            findsNothing,
          );
          expect(find.text(strings.text('gameplay.remoteTotal')), findsNothing);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
          profile.dispose();
          await tester.runAsync(saved.close);
          await h.close(tester);
          await tester.binding.setSurfaceSize(null);
        },
      );
    }
  }
}
