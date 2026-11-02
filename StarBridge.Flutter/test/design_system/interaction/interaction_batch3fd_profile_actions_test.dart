import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_action_button.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_activation_origin.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_models.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_draft.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_module.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_page.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_read_status.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_summary.dart';
import 'package:starbridge_flutter/design_system/icons/icon_semantic.dart';
import 'package:starbridge_flutter/design_system/icons/starbridge_icon.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../features/friends/social_layout_test.dart' show loadFonts, size;
import '../../features/personal_profile/profile_refresh_retention_test.dart'
    show HeldRefreshProfile;
import 'interaction_batch3fc_visibility_test.dart'
    show activateVisibility, visibilityFrames;
import 'interaction_batch3i_test.dart' show scopedApp;

Finder profileAction(String name) => find.byKey(Key('profile-$name'));

class ProfileActionsPort extends HeldRefreshProfile {
  final readSources = <InteractionSource>[];
  final writeSources = <InteractionSource>[];
  @override
  Future<PersonalProfileSnapshot> read() {
    readSources.add(currentStarBridgeActivationSource);
    return super.read();
  }

  @override
  Future<PersonalProfileActionResult> save(PersonalProfileEdit edit) {
    writeSources.add(currentStarBridgeActivationSource);
    return super.save(edit);
  }
}

class ProfileActionsHarness {
  ProfileActionsHarness(this.suite);
  InteractionSuite suite;
  bool reduce = false, light = false;
  final port = ProfileActionsPort();
  late final module = createPersonalProfileModule(port);
  PersonalProfileModule? replacement;
  bool away = false;
  late StateSetter update;
  Widget app() => StatefulBuilder(
    builder: (_, setState) {
      update = setState;
      return scopedApp(
        away
            ? const Text('away')
            : PersonalProfilePage(module: replacement ?? module),
        suite,
        reduce: reduce,
        light: light,
      );
    },
  );
}

Future<ProfileActionsHarness> mountProfileActions(
  WidgetTester t,
  InteractionSuite suite, {
  bool initialPending = false,
}) async {
  size(t, const Size(1100, 1100));
  final p = ProfileActionsHarness(suite);
  addTearDown(p.module.dispose);
  if (initialPending) {
    p.port.readGate = Completer();
    unawaited(p.module.initialize());
  } else {
    await p.module.initialize();
  }
  await t.pumpWidget(p.app());
  await visibilityFrames(t);
  return p;
}

StarBridgeActionButton _button(WidgetTester t, String key) =>
    t.widget<StarBridgeActionButton>(
      find
          .ancestor(
            of: profileAction(key),
            matching: find.byType(StarBridgeActionButton),
          )
          .first,
    );

void _wait(WidgetTester t, InteractionSuite suite, String input) {
  if (input != 'pointer') {
    expect(find.byType(SuiteProgressBar), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  } else if (suite != InteractionSuite.standard) {
    expect(find.byType(SuiteProgressBar), findsOneWidget);
  } else {
    expect(
      find.byType(LinearProgressIndicator).evaluate().isNotEmpty ||
          find.byType(CircularProgressIndicator).evaluate().isNotEmpty,
      isTrue,
    );
  }
}

void main() {
  setUpAll(loadFonts);
  testWidgets('standard refresh retains original outlined icon dimensions', (
    t,
  ) async {
    size(t, const Size(1100, 1100));
    final module = createPersonalProfileModule(ProfileActionsPort());
    addTearDown(module.dispose);
    await module.initialize();
    await t.pumpWidget(
      scopedApp(
        Column(
          children: [
            PersonalProfileSectionHeading(
              projection: module.projection.value,
              showOwnerActions: true,
              onPreview: () {},
              onEdit: () {},
              onRefresh: () {},
            ),
            IconButton.outlined(
              key: const Key('original-profile-refresh'),
              tooltip: 'Original refresh',
              onPressed: () {},
              icon: const StarBridgeIcon(StarBridgeIconSemantic.refresh),
            ),
          ],
        ),
        InteractionSuite.standard,
      ),
    );
    await visibilityFrames(t);
    expect(
      t.getSize(profileAction('refresh')),
      t.getSize(find.byKey(const Key('original-profile-refresh'))),
    );
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox.shrink());
  });
  for (final suite in InteractionSuite.values) {
    for (final input in ['pointer', 'keyboard', 'reader']) {
      testWidgets(
        '$suite $input retained refresh/failure/retry; preview/edit/cancel retain original owners',
        (t) async {
          final semantics = t.ensureSemantics();
          try {
            final p = await mountProfileActions(t, suite);
            final before = p.module.projection.value;
            p.port.readGate = Completer();
            await activateVisibility(t, profileAction('refresh'), input);
            expect(p.port.reads, 2);
            expect(
              p.port.readSources.last,
              input == 'pointer'
                  ? InteractionSource.pointer
                  : InteractionSource.keyboard,
            );
            expect(p.module.projection.value.callSign, before.callSign);
            expect(
              find.byKey(const Key('profile-identity-header')),
              findsOneWidget,
            );
            expect(_button(t, 'refresh').onActivate, isNull);
            expect(_button(t, 'edit').onActivate, isNull);
            _wait(t, suite, input);
            // A busy control's repeated gesture cannot schedule a second read.
            // Disabled suite targets intentionally IgnorePointer. Send a real
            // screen-coordinate gesture rather than demand they hit themselves.
            await t.tapAt(t.getCenter(profileAction('refresh')));
            await visibilityFrames(t);
            expect(p.port.reads, 2);
            p.port.readGate!.completeError(
              TimeoutException('controlled refresh refusal'),
            );
            await visibilityFrames(t);
            expect(p.module.projection.value.callSign, before.callSign);
            expect(p.module.projection.value.refreshFailed, isTrue);
            expect(profileAction('sync-failed'), findsOneWidget);
            expect(_button(t, 'edit').onActivate, isNull);
            expect(p.port.saves, 0);
            p.port.readGate = Completer();
            await activateVisibility(t, profileAction('sync-retry'), input);
            expect(p.port.reads, 3);
            _wait(t, suite, input);
            p.port.readGate!.complete(await p.port.delegate.read());
            await visibilityFrames(t);
            expect(profileAction('sync-failed'), findsNothing);
            expect(_button(t, 'edit').onActivate, isNotNull);
            await activateVisibility(t, profileAction('preview'), input);
            expect(profileAction('preview-exit'), findsOneWidget);
            expect(profileAction('edit'), findsNothing);
            expect(p.port.saves, 0);
            await activateVisibility(t, profileAction('preview-exit'), input);
            expect(profileAction('edit'), findsOneWidget);
            await activateVisibility(t, profileAction('edit'), input);
            expect(
              (p.module as PersonalProfileDraftSession).editingLeaseActive,
              isTrue,
            );
            expect(
              find.byKey(const Key('profile-editor-panel')),
              findsOneWidget,
            );
            expect(profileAction('refresh'), findsNothing);
            final about = find.byKey(const Key('profile-about-field'));
            await t.ensureVisible(about);
            await t.enterText(about, 'keep original profile draft owner');
            p.port.soft.add(null);
            await visibilityFrames(t);
            expect(p.port.reads, 3);
            expect(
              t.widget<TextField>(about).controller!.text,
              'keep original profile draft owner',
            );
            p.port.readGate = null;
            await activateVisibility(t, profileAction('edit-cancel'), input);
            expect(p.port.reads, 4);
            expect(p.port.saves, 0);
            expect(
              (p.module as PersonalProfileDraftSession).editingLeaseActive,
              isFalse,
            );
            expect(t.takeException(), isNull);
            await t.pumpWidget(const SizedBox.shrink());
          } finally {
            semantics.dispose();
          }
        },
      );

      testWidgets(
        '$suite $input first read and unavailable retries stay scoped, single-flight and live-reduced',
        (t) async {
          final semantics = t.ensureSemantics();
          try {
            final p = await mountProfileActions(t, suite, initialPending: true);
            expect(find.byType(PersonalProfileLoadingView), findsOneWidget);
            p.update(() => p.reduce = true);
            await visibilityFrames(t);
            _wait(t, suite, 'keyboard');
            p.port.readGate!.completeError(
              StateError('controlled initial failure'),
            );
            await visibilityFrames(t);
            expect(profileAction('unavailable'), findsOneWidget);
            p.update(() => p.reduce = false);
            await visibilityFrames(t);
            p.port.readGate = Completer();
            await activateVisibility(t, profileAction('retry'), input);
            expect(p.port.reads, 2);
            expect(_button(t, 'retry').onActivate, isNull);
            expect(profileAction('unavailable'), findsOneWidget);
            _wait(t, suite, input);
            await t.tapAt(t.getCenter(profileAction('retry')));
            await visibilityFrames(t);
            expect(p.port.reads, 2);
            p.update(() => p.reduce = true);
            await visibilityFrames(t);
            _wait(t, suite, 'keyboard');
            p.port.readGate!.completeError(
              StateError('controlled retry failure'),
            );
            await visibilityFrames(t);
            expect(_button(t, 'retry').onActivate, isNotNull);
            expect(p.port.reads, 2);
            p.port.readGate = null;
            await activateVisibility(t, profileAction('retry'), input);
            expect(p.port.reads, 3);
            expect(profileAction('unavailable'), findsNothing);
            expect(profileAction('edit'), findsOneWidget);
            expect(p.port.saves, 0);
            expect(t.takeException(), isNull);
            await t.pumpWidget(const SizedBox.shrink());
          } finally {
            semantics.dispose();
          }
        },
      );
    }

    testWidgets(
      '$suite keyboard read source ends with phase; following background update is not suppressed',
      (t) async {
        final p = await mountProfileActions(t, suite);
        p.port.readGate = Completer();
        await activateVisibility(t, profileAction('refresh'), 'keyboard');
        _wait(t, suite, 'keyboard');
        p.port.readGate!.complete(await p.port.delegate.read());
        await visibilityFrames(t);
        p.port.readGate = Completer();
        p.port.soft.add(null);
        await visibilityFrames(t);
        expect(p.port.reads, 3);
        _wait(t, suite, 'pointer');
        p.port.readGate!.complete(await p.port.delegate.read());
        await visibilityFrames(t);
        expect(p.port.saves, 0);
        await t.pumpWidget(const SizedBox.shrink());
      },
    );

    for (final replace in [false, true]) {
      testWidgets(
        '$suite ${replace ? 'replace' : 'leave'} page during refresh; late refusal has no new-page effect',
        (t) async {
          final p = await mountProfileActions(t, suite);
          p.port.readGate = Completer();
          await activateVisibility(t, profileAction('refresh'), 'pointer');
          final other = createPersonalProfileModule(ProfileActionsPort());
          addTearDown(other.dispose);
          await other.initialize();
          p.update(() {
            if (replace) {
              p.replacement = other;
            } else {
              p.away = true;
            }
          });
          await visibilityFrames(t);
          p.port.readGate!.completeError(
            TimeoutException('late response for old view'),
          );
          await visibilityFrames(t);
          expect(other.projection.value.refreshFailed, isFalse);
          expect(profileAction('sync-failed'), findsNothing);
          expect(find.byType(SuiteProgressBar), findsNothing);
          if (replace) expect(_button(t, 'edit').onActivate, isNotNull);
          expect(p.port.saves, 0);
          expect(t.takeException(), isNull);
          await t.pumpWidget(const SizedBox.shrink());
        },
      );
    }
  }
}
