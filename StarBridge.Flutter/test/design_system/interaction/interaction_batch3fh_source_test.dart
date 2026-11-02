import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/icons/starbridge_icon.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_activation_origin.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_segmented_control.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_select_form_field.dart';
import 'package:starbridge_flutter/features/settings/bridge_notification_sources.dart';
import 'package:starbridge_flutter/features/settings/notification_editor_frame.dart';
import 'package:starbridge_flutter/features/settings/notification_settings_models.dart';
import 'package:starbridge_flutter/features/settings/notification_settings_sources.dart';
import 'package:starbridge_flutter/features/settings/notification_sources_connected_panel.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../features/friends/social_layout_test.dart' show loadFonts, size;
import 'interaction_batch3fc_visibility_test.dart' show visibilityFrames;
import 'interaction_batch3i_test.dart' show scopedApp;

const sourceRule = NotificationSourceRule(
  sourceRef: 'official-fleet:aster',
  kind: NotificationSourceKind.officialFleet,
  displayName: 'Aster fleet',
  contextLabel: 'Alpha',
  mode: NotificationSourceMode.normal,
);

Finder sourceControl() =>
    find.byType(StarBridgeSegmentedControl<NotificationSourceMode>);
Finder sourceSegment(String label, {Finder? within}) =>
    find.descendant(of: within ?? sourceControl(), matching: find.text(label));

/// No direct onChanged calls or programmatic requestFocus: all three inputs
/// enter the same mounted control through their actual user-facing path.
Future<void> sourceActivate(
  WidgetTester t,
  String label,
  String input, {
  Finder? within,
}) async {
  final target = sourceSegment(label, within: within);
  expect(target, findsOneWidget);
  await t.ensureVisible(target);
  if (input == 'reader') {
    final semantic = find.bySemanticsLabel(
      RegExp('^${RegExp.escape(label)}\$'),
    );
    expect(semantic, findsOneWidget);
    final node = t.getSemantics(semantic);
    expect(node.getSemanticsData().hasAction(ui.SemanticsAction.tap), isTrue);
    t.binding.renderViews.single.owner!.semanticsOwner!.performAction(
      node.id,
      ui.SemanticsAction.tap,
    );
  } else if (input == 'keyboard') {
    final node = Focus.of(t.element(target));
    expect(node.canRequestFocus, isTrue);
    FocusScope.of(t.element(target)).unfocus();
    await t.pump();
    await t.pump();
    for (var i = 0; !node.hasPrimaryFocus && i < 40; i++) {
      await t.sendKeyEvent(LogicalKeyboardKey.tab);
      await t.pump();
      await t.pump();
    }
    expect(
      node.hasPrimaryFocus,
      isTrue,
      reason: 'target=$node\n${FocusManager.instance.toStringDeep()}',
    );
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
  } else {
    await t.tap(target);
  }
  await t.pump();
  await t.pump();
}

void expectProjected(WidgetTester t, NotificationSourceMode mode) {
  expect(
    t
        .widget<StarBridgeSegmentedControl<NotificationSourceMode>>(
          sourceControl(),
        )
        .value,
    mode,
  );
  final native = find.byType(SegmentedButton<NotificationSourceMode>);
  if (native.evaluate().isNotEmpty) {
    expect(t.widget<SegmentedButton<NotificationSourceMode>>(native).selected, {
      mode,
    });
  } else {
    expect(
      t.widget<SuiteSelectionTrack>(find.byType(SuiteSelectionTrack)).selected,
      mode.index,
    );
  }
}

class SourceIntent {
  SourceIntent(this.mode) : before = currentStarBridgeActivationSource;
  final NotificationSourceMode mode;
  final InteractionSource before;
  InteractionSource? after;
  final result = Completer<bool>();
}

class SourceProbe {
  SourceProbe(this.suite);
  final InteractionSuite suite;
  final requests = <SourceIntent>[];
  NotificationSourceRule rule = sourceRule;
  bool enabled = true, reduce = false, light = false, shown = true;
  double width = 850, scale = 1;
  late StateSetter update;
  Widget app() => StatefulBuilder(
    builder: (_, setState) {
      update = setState;
      return scopedApp(
        Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: Semantics(
              explicitChildNodes: true,
              child: SizedBox(
                width: width,
                child: shown
                    ? NotificationSourceRuleRow(
                        rule: rule,
                        enabled: enabled,
                        onChanged: (mode) async {
                          final request = SourceIntent(mode);
                          requests.add(request);
                          final accepted = await request.result.future;
                          request.after = currentStarBridgeActivationSource;
                          return accepted;
                        },
                      )
                    : const Text('Left source rules'),
              ),
            ),
          ),
        ),
        suite,
        reduce: reduce,
        light: light,
      );
    },
  );
}

class SourceWrite {
  SourceWrite(this.original, Map<String, NotificationSourceMode> modes)
    : modes = Map.of(modes);
  final NotificationSourcesValue original;
  final Map<String, NotificationSourceMode> modes;
  final reply = Completer<NotificationSourcesValue>();
}

class HeldSourcePort implements NotificationSourcesPort {
  final events = StreamController<void>.broadcast();
  NotificationSourcesValue authoritative = NotificationSourcesValue(17, [
    sourceRule,
  ]);
  final writes = <SourceWrite>[];
  int reads = 0;
  @override
  Stream<void> get invalidations => events.stream;
  @override
  Future<NotificationSourcesValue> read() async {
    reads++;
    return authoritative;
  }

  @override
  Future<NotificationSourcesValue> save(
    NotificationSourcesValue original,
    Map<String, NotificationSourceMode> modes,
  ) {
    final write = SourceWrite(original, modes);
    writes.add(write);
    return write.reply.future;
  }

  @override
  void dispose() => unawaited(events.close());
}

void main() {
  setUpAll(loadFonts);
  for (final suite in InteractionSuite.values) {
    for (final input in ['pointer', 'keyboard', 'reader']) {
      testWidgets(
        '3fh $suite $input controlled refusal, async origin, late result',
        (t) async {
          size(t, const Size(1100, 900));
          final semantics = t.ensureSemantics();
          final p = SourceProbe(suite);
          await t.pumpWidget(p.app());
          await visibilityFrames(t);
          expect(
            find.descendant(
              of: sourceControl(),
              matching: find.byType(StarBridgeIcon),
            ),
            findsNWidgets(3),
          );
          final key = find.byKey(
            const Key('notification-source-mode-official-fleet:aster'),
          );
          expect(key, findsOneWidget);
          expect(
            t.widget(key),
            suite == InteractionSuite.standard
                ? isA<SegmentedButton<NotificationSourceMode>>()
                : isA<SuiteSelectionTrack>(),
          );
          await sourceActivate(t, '仅关键变化', input);
          expect(p.requests, hasLength(1));
          expect(p.requests.single.mode, NotificationSourceMode.importantOnly);
          final expectedSource = input == 'pointer'
              ? InteractionSource.pointer
              : InteractionSource.keyboard;
          expect(p.requests.single.before, expectedSource);
          expectProjected(t, NotificationSourceMode.normal);
          // A failed asynchronous owner callback must never become a selection.
          p.requests.single.result.complete(false);
          await visibilityFrames(t);
          expect(p.requests.single.after, expectedSource);
          expectProjected(t, NotificationSourceMode.normal);
          await sourceActivate(t, '免打扰', input);
          expect(p.requests, hasLength(2));
          p.requests.last.result.complete(true);
          await visibilityFrames(t);
          expect(p.requests.last.after, expectedSource);
          // Even true is not authority; only a new parent projection changes it.
          expectProjected(t, NotificationSourceMode.normal);
          p.update(
            () => p.rule = sourceRule.copyWith(
              mode: NotificationSourceMode.doNotDisturb,
            ),
          );
          await visibilityFrames(t);
          expectProjected(t, NotificationSourceMode.doNotDisturb);
          await sourceActivate(t, '免打扰', input);
          expect(
            p.requests,
            hasLength(2),
            reason: 'selected value is not a new edit',
          );
          await sourceActivate(t, '正常提醒', input);
          expect(p.requests, hasLength(3));
          p.update(() => p.shown = false);
          await t.pump();
          p.requests.last.result.complete(true);
          await visibilityFrames(t);
          expect(find.text('Left source rules'), findsOneWidget);
          expect(t.takeException(), isNull);
          await t.pumpWidget(const SizedBox());
          semantics.dispose();
        },
      );

      testWidgets(
        '3fh $suite $input legacy and additive delegate, controlled feedback',
        (t) async {
          size(t, const Size(900, 700));
          final semantics = t.ensureSemantics();
          var selected = 0;
          var oldCalls = 0, newCalls = 0;
          var useNew = false, enabled = true, reduce = false, light = false;
          final origins = <InteractionSource>[];
          late StateSetter update;
          await t.pumpWidget(
            StatefulBuilder(
              builder: (_, setState) {
                update = setState;
                return scopedApp(
                  Semantics(
                    explicitChildNodes: true,
                    child: SizedBox(
                      width: 430,
                      child: StarBridgeSegmentedControl<int>(
                        value: selected,
                        segments: [
                          for (var i = 0; i < 3; i++)
                            StarBridgeSegment(
                              value: i,
                              label: 'Choice $i',
                              icon: useNew
                                  ? Icon(Icons.star, key: Key('choice-icon-$i'))
                                  : null,
                            ),
                        ],
                        onChanged: enabled
                            ? (value) {
                                oldCalls++;
                                origins.add(currentStarBridgeActivationSource);
                                update(() => selected = value);
                              }
                            : null,
                        onActivate: !enabled || !useNew
                            ? null
                            : (value, source) {
                                newCalls++;
                                expect(
                                  currentStarBridgeActivationSource,
                                  source,
                                );
                                origins.add(source);
                                update(() => selected = value);
                              },
                      ),
                    ),
                  ),
                  suite,
                  reduce: reduce,
                  light: light,
                );
              },
            ),
          );
          await visibilityFrames(t);
          final control = find.byType(StarBridgeSegmentedControl<int>);
          await sourceActivate(t, 'Choice 1', input, within: control);
          expect(oldCalls, 1);
          expect(selected, 1);
          expect(origins, [
            input == 'pointer'
                ? InteractionSource.pointer
                : InteractionSource.keyboard,
          ]);
          if (suite != InteractionSuite.standard && input != 'pointer') {
            final track = t.state<SuiteSelectionTrackState>(
              find.byType(SuiteSelectionTrack),
            );
            expect(
              track.isStretching || track.isSweeping || track.isRinging,
              isFalse,
            );
          }
          update(() => useNew = true);
          await visibilityFrames(t);
          for (var i = 0; i < 3; i++) {
            expect(find.byKey(Key('choice-icon-$i')), findsOneWidget);
          }
          await sourceActivate(t, 'Choice 2', input, within: control);
          expect(
            oldCalls,
            1,
            reason: 'new source-aware delegate wins, not two callbacks',
          );
          expect(newCalls, 1);
          expect(selected, 2);
          expect(
            origins.last,
            input == 'pointer'
                ? InteractionSource.pointer
                : InteractionSource.keyboard,
          );
          update(() {
            reduce = true;
            light = true;
          });
          await t.pump();
          await t.pump();
          if (suite != InteractionSuite.standard) {
            final track = t.state<SuiteSelectionTrackState>(
              find.byType(SuiteSelectionTrack),
            );
            expect(
              track.isStretching || track.isSweeping || track.isRinging,
              isFalse,
            );
          }
          await sourceActivate(t, 'Choice 0', input, within: control);
          expect(newCalls, 2);
          expect(selected, 0);
          update(() => enabled = false);
          await visibilityFrames(t);
          for (final label in ['Choice 0', 'Choice 1', 'Choice 2']) {
            final node = t.getSemantics(
              find.bySemanticsLabel(RegExp('^${RegExp.escape(label)}\$')),
            );
            expect(
              node.getSemanticsData().hasAction(ui.SemanticsAction.tap),
              isFalse,
            );
          }
          await t.tapAt(
            t.getCenter(sourceSegment('Choice 1', within: control)),
          );
          await visibilityFrames(t);
          expect(oldCalls, 1);
          expect(newCalls, 2);
          expect(selected, 0);
          expect(t.takeException(), isNull);
          await t.pumpWidget(const SizedBox());
          semantics.dispose();
        },
      );
    }

    testWidgets(
      '3fh $suite active rapid choices, disabled and unchanged narrow selector',
      (t) async {
        size(t, const Size(1100, 900));
        final semantics = t.ensureSemantics();
        final p = SourceProbe(suite);
        await t.pumpWidget(p.app());
        await visibilityFrames(t);
        // Every genuine action still reaches the owner; no high-frequency gate.
        for (final label in ['仅关键变化', '免打扰', '仅关键变化', '免打扰']) {
          await sourceActivate(t, label, 'pointer');
        }
        expect(p.requests.map((e) => e.mode), [
          NotificationSourceMode.importantOnly,
          NotificationSourceMode.doNotDisturb,
          NotificationSourceMode.importantOnly,
          NotificationSourceMode.doNotDisturb,
        ]);
        p.update(() {
          p.enabled = false;
          p.reduce = true;
          p.light = true;
          p.scale = 1.5;
        });
        await visibilityFrames(t);
        expectProjected(t, NotificationSourceMode.normal);
        for (final label in ['正常提醒', '仅关键变化', '免打扰']) {
          final node = t.getSemantics(
            find.bySemanticsLabel(RegExp('^${RegExp.escape(label)}\$')),
          );
          expect(
            node.getSemanticsData().hasAction(ui.SemanticsAction.tap),
            isFalse,
          );
        }
        await t.tapAt(t.getCenter(sourceSegment('仅关键变化')));
        await t.pump();
        expect(p.requests, hasLength(4));
        p.update(() {
          p.width = 360;
          p.enabled = true;
        });
        await visibilityFrames(t);
        expect(sourceControl(), findsNothing);
        expect(
          find.byType(StarBridgeSelectFormField<NotificationSourceMode>),
          findsOneWidget,
        );
        for (final request in p.requests) {
          request.result.complete(false);
        }
        await visibilityFrames(t);
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
        semantics.dispose();
      },
    );

    testWidgets(
      '3fh $suite actual drafts preserve refusal, retry revision and discard',
      (t) async {
        size(t, const Size(1100, 1100));
        final port = HeldSourcePort();
        final owner = Object();
        await t.pumpWidget(
          scopedApp(
            SizedBox(
              width: 850,
              child: NotificationEditorFrame(
                owner: owner,
                child: SingleChildScrollView(
                  child: NotificationSourcesConnectedPanel(port: port),
                ),
              ),
            ),
            suite,
          ),
        );
        await visibilityFrames(t);
        expect(port.reads, 1);
        await sourceActivate(t, '仅关键变化', 'pointer');
        expect(
          port.writes,
          isEmpty,
          reason: 'selection edits a draft, never commits itself',
        );
        expectProjected(t, NotificationSourceMode.importantOnly);
        await t.tap(find.byKey(const Key('notification-save')));
        await visibilityFrames(t);
        expect(port.writes, hasLength(1));
        expect(port.writes.single.original.revision, 17);
        expect(port.writes.single.modes, {
          'official-fleet:aster': NotificationSourceMode.importantOnly,
        });
        expect(
          t
              .widget<StarBridgeSegmentedControl<NotificationSourceMode>>(
                sourceControl(),
              )
              .onActivate,
          isNull,
        );
        port.writes.single.reply.completeError(StateError('rejected'));
        await visibilityFrames(t);
        expectProjected(t, NotificationSourceMode.importantOnly);
        expect(
          t
              .widget<StarBridgeSegmentedControl<NotificationSourceMode>>(
                sourceControl(),
              )
              .onActivate,
          isNull,
        );
        await t.tap(find.byKey(const Key('notification-save')));
        await visibilityFrames(t);
        expect(port.writes, hasLength(2));
        expect(port.writes.last.original.revision, 17);
        expect(port.writes.last.modes, port.writes.first.modes);
        port.authoritative = NotificationSourcesValue(18, [
          sourceRule.copyWith(mode: NotificationSourceMode.importantOnly),
        ]);
        port.writes.last.reply.complete(port.authoritative);
        await visibilityFrames(t);
        expectProjected(t, NotificationSourceMode.importantOnly);
        await sourceActivate(t, '免打扰', 'pointer');
        await t.tap(find.byKey(const Key('notification-discard')));
        await visibilityFrames(t);
        expectProjected(t, NotificationSourceMode.importantOnly);
        expect(port.writes, hasLength(2));
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
        port.dispose();
      },
    );
  }
}
