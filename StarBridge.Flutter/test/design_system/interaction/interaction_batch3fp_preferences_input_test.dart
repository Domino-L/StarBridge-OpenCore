import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/bootstrap/starbridge_app.dart';
import 'package:starbridge_flutter/app/composition/app_composition.dart';
import 'package:starbridge_flutter/app/preferences/app_preferences.dart';
import 'package:starbridge_flutter/app/preferences/app_preferences_projection.dart';
import 'package:starbridge_flutter/app/preferences/app_preferences_store.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_interaction_theme.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_segmented_control.dart';
import 'package:starbridge_flutter/features/settings/general_settings_interaction.dart';
import 'package:starbridge_flutter/features/settings/general_settings_motion.dart';
import 'package:starbridge_flutter/features/settings/general_settings_page.dart';
import 'package:starbridge_flutter/platform/window/in_memory_window_chrome.dart';
import 'package:starbridge_flutter/shared/release/official_client_profile.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../features/friends/social_layout_test.dart' show loadFonts, size;
import 'interaction_batch3b_test.dart' show exposedNodes;
import 'interaction_batch3fa_host_preferences_test.dart'
    show InteractionHostPreferencesFixture;

// Actual GeneralSettingsPage input -> existing preference owner -> original
// isolated C# dispatcher/store -> live StarBridgeApp -> a new process/owner/app.
// This is not full product Host/named-pipe or independent-engine acceptance;
// auxiliary send/receive coverage remains the separate 3fa/receiver tests.
const _page = Key('3fp-actual-general-settings');
const _control = Key('general-interaction-style');
const _timeout = Timeout(Duration(seconds: 60));

Finder _adapter() => find.byType(StarBridgeSegmentedControl<InteractionStyle>);

StarBridgeSegmentedControl<InteractionStyle> _config(WidgetTester t) =>
    t.widget<StarBridgeSegmentedControl<InteractionStyle>>(_adapter());

Finder _label(WidgetTester t, InteractionStyle style) {
  final label = _config(t).segments
      .singleWhere((item) => item.value == style)
      .label;
  return find.descendant(of: _adapter(), matching: find.text(label));
}

String _labelText(WidgetTester t, InteractionStyle style) =>
    _config(t).segments.singleWhere((item) => item.value == style).label;

Future<void> _frames(WidgetTester t, [int count = 2]) async {
  for (var i = 0; i < count; i++) {
    await t.pump();
  }
}

Future<void> _showSettings(
  WidgetTester t,
  InteractionHostPreferencesFixture fixture,
) async {
  final nav = GlobalKey<NavigatorState>();
  final composition = AppComposition.forTest(
    preferences: fixture.owner,
    windowChrome: InMemoryWindowChrome(),
  );
  await t.pumpWidget(
    StarBridgeApp(composition: composition, navigatorKey: nav),
  );
  await t.pumpAndSettle();
  unawaited(
    nav.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          body: GeneralSettingsPage(key: _page, preferences: fixture.owner),
        ),
      ),
    ),
  );
  await t.pumpAndSettle();
  expect(find.byType(GeneralSettingsPage), findsOneWidget);
  expect(find.byKey(_control), findsOneWidget);
  expect(_adapter(), findsOneWidget);
}

void _liveStyle(WidgetTester t, InteractionStyle expected) {
  expect(_config(t).value, expected);
  expect(
    t
        .widget<GeneralSettingsInteraction>(
          find.byType(GeneralSettingsInteraction),
        )
        .value,
    expected,
  );
  expect(
    InteractionScope.of(t.element(find.byKey(_page))).suite,
    interactionSuiteFromName(expected.name),
    reason: 'The actual page inherits the live main application scope',
  );
  final root = t.widget<StarBridgeInteractionConfiguration>(
    find.byType(StarBridgeInteractionConfiguration).first,
  );
  expect(root.suite, interactionSuiteFromName(expected.name));
}

Future<void> _selectByInput(
  WidgetTester t,
  InteractionStyle style,
  String input,
) async {
  final target = _label(t, style);
  expect(target, findsOneWidget);
  await t.ensureVisible(target);
  await t.pumpAndSettle();
  if (input == 'pointer') {
    await t.tap(target);
  } else if (input == 'keyboard') {
    // Inspect the actual label's SDK/shared focus ancestry, but acquire it
    // exclusively through Tab. Do not requestFocus or invoke a callback.
    var tabs = 0;
    while (!(Focus.maybeOf(t.element(target))?.hasPrimaryFocus ?? false) &&
        tabs < 128) {
      await t.sendKeyEvent(LogicalKeyboardKey.tab);
      await _frames(t);
      tabs++;
    }
    final focus = Focus.maybeOf(t.element(target));
    expect(focus, isNotNull);
    expect(
      focus!.hasPrimaryFocus,
      isTrue,
      reason: 'Real Tab traversal must reach ${_labelText(t, style)}',
    );
    expect(FocusManager.instance.primaryFocus, same(focus));
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
  } else {
    final label = _labelText(t, style);
    final nodes = exposedNodes(t).where((node) {
      final data = node.getSemanticsData();
      return data.label == label && data.hasAction(SemanticsAction.tap);
    }).toList();
    expect(nodes, hasLength(1));
    t.binding.renderViews.single.owner!.semanticsOwner!.performAction(
      nodes.single.id,
      SemanticsAction.tap,
    );
  }
  await _frames(t);
}

Future<void> _waitForReceipt(
  WidgetTester t,
  InteractionHostPreferencesFixture fixture,
) async {
  final deadline = (await t.runAsync(
    () async => DateTime.now().add(const Duration(seconds: 8)),
  ))!;
  while (fixture.owner.projection.value.operation ==
      AppPreferencesOperation.saving) {
    // Transport runs in the real event loop, but this save originated in the
    // widget input/FakeAsync zone. Return there and pump its microtasks/frames
    // rather than holding runAsync open while waiting for the UI's Future.
    final now = (await t.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 5));
      return DateTime.now();
    }))!;
    await t.pump();
    await t.pump();
    if (now.isAfter(deadline) &&
        fixture.owner.projection.value.operation ==
            AppPreferencesOperation.saving) {
      fail('Original Host reply did not settle the original preference owner');
    }
  }
}

void _disabledOptions(WidgetTester t) {
  final config = _config(t);
  expect(config.onChanged, isNull);
  expect(config.onActivate, isNull);
  final exposed = exposedNodes(t)
      .map((node) => node.getSemanticsData())
      .toList();
  for (final option in config.segments) {
    final nodes = exposed.where((data) => data.label == option.label).toList();
    expect(nodes, hasLength(1));
    expect(
      nodes.single.hasAction(SemanticsAction.tap),
      isFalse,
      reason: 'Saving must not expose another selectable ${option.value}',
    );
  }
}

void main() {
  setUpAll(loadFonts);
  for (final style in InteractionStyle.values) {
    for (final rejected in [false, true]) {
      for (final input in ['pointer', 'keyboard', 'reader']) {
        testWidgets(
          '3fp $style $input actual settings ${rejected ? 'rejects' : 'confirms'} '
          'and new Host owner app restores committed choice',
          (t) async {
            size(t, const Size(1280, 1000));
            final semantics = t.ensureSemantics();
            final fixture = (await t.runAsync(
              InteractionHostPreferencesFixture.start,
            ))!;
            InteractionHostPreferencesFixture? reopened;
            try {
              final baseline = InteractionStyle.values[(style.index + 1) % 4];
              // Seed only: make even Standard an unselected option. The action
              // under test below always comes from real page input, never this
              // owner method, onChanged, or any saved callback.
              await t.runAsync(() async {
                expect(
                  await fixture.owner.setInteractionStyle(baseline),
                  isTrue,
                );
              });
              await _showSettings(t, fixture);
              _liveStyle(t, baseline);
              final before = fixture.owner.projection.value;
              final writesBefore = fixture.updateRequests;
              await t.runAsync(
                () => fixture.configureHeldSave(rejected: rejected),
              );
              await _selectByInput(t, style, input);
              final held = (await t.runAsync(fixture.heldEvent))!;
              await _frames(t);

              final pending = fixture.owner.projection.value;
              expect(pending.operation, AppPreferencesOperation.saving);
              expect(pending.confirmed!.interactionStyle, baseline);
              expect(pending.revision, before.revision);
              expect(pending.canEdit, isFalse);
              expect(held['committed'], !rejected);
              expect(
                (held['snapshot'] as Map)['interactionStyle'],
                rejected ? baseline.name : style.name,
              );
              _liveStyle(t, style);
              final waiting = t.widget<GeneralSettingsWaiting>(
                find.byType(GeneralSettingsWaiting),
              );
              expect(waiting.saving, isTrue);
              expect(
                waiting.source,
                input == 'pointer'
                    ? InteractionSource.pointer
                    : InteractionSource.keyboard,
              );
              expect(fixture.updateRequests, writesBefore + 1);
              _disabledOptions(t);

              // Hit an actual different segment while disabled. IgnorePointer
              // removes advanced faces from hit testing, so use its exact
              // on-screen coordinates rather than a misleading tap warning.
              final other = InteractionStyle.values[(style.index + 2) % 4];
              await t.ensureVisible(_label(t, other));
              await _frames(t);
              await t.tapAt(t.getCenter(_label(t, other)));
              await _frames(t);
              _disabledOptions(t);
              _liveStyle(t, style);
              expect(fixture.updateRequests, writesBefore + 1);
              expect(fixture.owner.projection.value.revision, before.revision);

              await t.runAsync(fixture.release);
              await _waitForReceipt(t, fixture);
              await _frames(t);
              final committed = rejected ? baseline : style;
              final after = fixture.owner.projection.value;
              expect(after.operation, AppPreferencesOperation.idle);
              expect(after.canEdit, isTrue);
              expect(after.confirmed!.interactionStyle, committed);
              expect(after.revision, before.revision! + (rejected ? 0 : 1));
              expect(
                after.failure,
                rejected ? AppPreferencesFailure.saveFailed : null,
              );
              expect(_config(t).onChanged, isNotNull);
              _liveStyle(t, committed);
              expect(fixture.updateRequests, writesBefore + 1);

              final root = fixture.root;
              final expectedRevision = after.revision;
              await t.pumpWidget(const SizedBox());
              await _frames(t);
              await t.runAsync(fixture.close);
              reopened = await t.runAsync(
                () => InteractionHostPreferencesFixture.start(root: root),
              );
              final fresh = reopened!;
              expect(fresh.root, root);
              expect(
                fresh.updateRequests,
                0,
                reason: 'Reopen only reads, never replays UPDATE',
              );
              final restored = fresh.owner.projection.value;
              expect(restored.source, AppPreferencesSource.stored);
              expect(restored.confirmed!.interactionStyle, committed);
              expect(restored.effective.interactionStyle, committed);
              expect(restored.revision, expectedRevision);
              expect(restored.failure, isNull);
              await _showSettings(t, fresh);
              _liveStyle(t, committed);
              expect(_config(t).onChanged, isNotNull);
              expect(fresh.updateRequests, 0);
              expect(t.takeException(), isNull);
            } finally {
              await t.pumpWidget(const SizedBox());
              await _frames(t);
              await t.runAsync(fixture.close);
              if (reopened != null) await t.runAsync(reopened.close);
              semantics.dispose();
            }
          },
          timeout: _timeout,
          // The official release profile intentionally hides this control;
          // absent original worker/data or advanced UI is SKIP, never PASS.
          skip:
              !InteractionHostPreferencesFixture.available ||
              !OfficialClientProfile.advancedInteractions,
        );
      }
    }
  }
}
