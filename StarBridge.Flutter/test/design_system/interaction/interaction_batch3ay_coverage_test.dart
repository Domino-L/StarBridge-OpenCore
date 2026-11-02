import 'dart:async';
import 'dart:io';
import 'dart:ui' show ImageByteFormat, SemanticsAction, Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/services.dart';
import 'package:flutter/semantics.dart' show SemanticsNode;
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_activation_origin.dart';
import 'package:starbridge_flutter/features/settings/notification_settings_common.dart';
import 'package:starbridge_flutter/features/settings/notification_settings_channels.dart';
import 'package:starbridge_flutter/features/settings/notification_settings_page.dart';
import 'package:starbridge_flutter/features/settings/notification_settings_models.dart';
import 'package:starbridge_flutter/features/settings/notification_settings_module.dart';
import 'package:starbridge_flutter/features/settings/notification_settings_port.dart';
import 'package:starbridge_flutter/features/settings/in_memory_notification_settings_adapter.dart';
import 'package:starbridge_flutter/features/settings/desktop_notification_test_button.dart';
import 'package:starbridge_flutter/platform/host/desktop_notification_port.dart';

import 'interaction_batch3ae_test.dart' show mount;
import '../../features/friends/social_layout_test.dart' show loadFonts;

const rowKey = Key('notification-row-probe');
const desktopKey = Key('notification-desktop-test');

Future<void> frame(WidgetTester t) async {
  await t.pump();
  await t.pump();
}

Future<void> activate(WidgetTester t, Finder target, String source) async {
  await t.ensureVisible(target);
  if (source == 'pointer') {
    await t.tapAt(t.getCenter(target));
  } else if (source == 'keyboard') {
    final targetControl = t.widget(target);
    final ownDetectors = targetControl is SuitePressable
        ? find.descendant(
            of: target,
            matching: find.byType(FocusableActionDetector),
          )
        : null;
    final ownFocus = targetControl is SuitePressable
        ? targetControl.focusNode ??
              (ownDetectors!.evaluate().length == 1
                  ? t.widget<FocusableActionDetector>(ownDetectors).focusNode
                  : null)
        : null;
    if (ownFocus != null) {
      expect(ownFocus.canRequestFocus, isTrue);
      ownFocus.requestFocus();
      await t.pump();
      expect(FocusManager.instance.primaryFocus, same(ownFocus));
    } else {
      final ancestor = find.ancestor(
        of: target,
        matching: find.byType(SuitePressable),
      );
      final pressable = ancestor.evaluate().isEmpty
          ? null
          : t.widget<SuitePressable>(ancestor.first);
      if (pressable?.focusNode != null) {
        pressable!.focusNode!.requestFocus();
      } else {
        final text = find
            .descendant(of: target, matching: find.byType(Text))
            .first;
        Focus.of(t.element(text)).requestFocus();
      }
    }
    await t.pumpAndSettle();
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
  } else {
    final node = t.getSemantics(target);
    expect(node.getSemanticsData().hasAction(SemanticsAction.tap), true);
    t.binding.renderViews.single.owner!.semanticsOwner!.performAction(
      node.id,
      SemanticsAction.tap,
    );
  }
}

int labelledActions(WidgetTester t, String label) {
  var count = 0;
  void visit(SemanticsNode node) {
    final data = node.getSemanticsData();
    if (data.label == label && data.hasAction(SemanticsAction.tap)) count++;
    node.visitChildren((child) {
      visit(child);
      return true;
    });
  }

  visit(t.binding.renderViews.single.owner!.semanticsOwner!.rootSemanticsNode!);
  return count;
}

class Port implements DesktopNotificationPort {
  final answers = <Completer<bool>>[];
  int clears = 0;
  bool? lastTest;
  @override
  Future<bool> show(
    String title,
    String message, {
    bool test = false,
    String? ticket,
  }) {
    lastTest = test;
    final answer = Completer<bool>();
    answers.add(answer);
    return answer.future;
  }

  @override
  Future<void> clear() async {
    clears++;
  }
}

class Diagnostics extends Port implements DesktopNotificationDiagnostics {
  final diagnosticAnswers = <Completer<DesktopNotificationTestResult>>[];
  @override
  Future<DesktopNotificationTestResult> testDesktop() {
    final answer = Completer<DesktopNotificationTestResult>();
    diagnosticAnswers.add(answer);
    return answer.future;
  }
}

class CountingPort implements NotificationSettingsPort {
  final inner = InMemoryNotificationSettingsAdapter.forReview();
  int reads = 0, writes = 0;
  @override
  Stream<void> get invalidations => const Stream.empty();
  @override
  Future<NotificationSettingsSnapshot> read() {
    reads++;
    return inner.read();
  }

  @override
  Future<NotificationSettingsWriteResult> update(
    NotificationSettingsValue settings, {
    required int expectedRevision,
  }) {
    writes++;
    return inner.update(settings, expectedRevision: expectedRevision);
  }

  @override
  Future<void> close() => inner.close();
}

void main() {
  setUpAll(loadFonts);
  for (final suite in InteractionSuite.values) {
    for (final source in ['pointer', 'keyboard', 'reader']) {
      for (final body in [false, true]) {
        testWidgets(
          '$suite row $source body=$body calls once with projected value',
          (t) async {
            final handle = t.ensureSemantics();
            var value = false, calls = 0;
            InteractionSource? origin;
            await mount(
              t,
              StatefulBuilder(
                builder: (context, update) => NotificationToggleRow(
                  settingKey: rowKey,
                  value: value,
                  enabled: true,
                  titleKey: 'settings.notification.local.enabled',
                  descriptionKey:
                      'settings.notification.local.enabledDescription',
                  badgeKey: 'settings.notification.scope.device',
                  leading: const Icon(Icons.notifications),
                  onChanged: (next) async {
                    calls++;
                    origin = currentStarBridgeActivationSource;
                    update(() => value = next);
                    return true;
                  },
                ),
              ),
              suite,
            );
            var target = find.byKey(rowKey);
            if (body && source == 'pointer') {
              target = find.text(
                AppStrings.of(t.element(target))
                    .text('settings.notification.local.enabled'),
              );
            }
            await activate(t, target, source);
            await frame(t);
            expect(calls, 1);
            expect(value, true);
            expect(
              origin,
              source == 'pointer'
                  ? InteractionSource.pointer
                  : InteractionSource.keyboard,
            );
            final node = t.getSemantics(find.byKey(rowKey)).getSemanticsData();
            expect(labelledActions(t, node.label), 1);
            expect(node.flagsCollection.isToggled, Tristate.isTrue);
            expect(node.hasAction(SemanticsAction.tap), true);
            await t.pumpWidget(const SizedBox());
            handle.dispose();
          },
        );
      }
      testWidgets(
        '$suite preview $source retains original choice payload and no repeat save',
        (t) async {
          final handle = t.ensureSemantics();
          var calls = 0;
          var value =
              InMemoryNotificationSettingsAdapter.forReview().current.settings!;
          InteractionSource? origin;
          await mount(
            t,
            StatefulBuilder(
              builder: (context, update) => SingleChildScrollView(
                child: NotificationPreviewPanel(
                  settings: value,
                  enabled: true,
                  onSave: (next) async {
                    origin = currentStarBridgeActivationSource;
                    calls++;
                    update(() => value = next);
                    return true;
                  },
                ),
              ),
            ),
            suite,
          );
          final choice = find.byKey(
            const Key('notification-preview-hiddenDetails'),
          );
          await activate(t, choice, source);
          await frame(t);
          expect(value.previewMode, NotificationPreviewMode.hiddenDetails);
          expect(calls, 1);
          expect(
            origin,
            source == 'pointer'
                ? InteractionSource.pointer
                : InteractionSource.keyboard,
          );
          expect(
            t
                .getSemantics(choice)
                .getSemanticsData()
                .flagsCollection
                .isSelected,
            Tristate.isTrue,
          );
          await activate(t, choice, source);
          await frame(t);
          expect(calls, 1);
          await t.pumpWidget(const SizedBox());
          handle.dispose();
        },
      );
      for (final result in [false, true]) {
        testWidgets(
          '$suite desktop $source result=$result preserves submission and busy guard',
          (t) async {
            final handle = t.ensureSemantics();
            final port = Port();
            await mount(
              t,
              DesktopNotificationTestButton(port: port, enabled: true),
              suite,
            );
            final button = find.byKey(desktopKey);
            await activate(t, button, source);
            await frame(t);
            expect(port.answers.length, 1);
            expect(port.lastTest, true);
            final node = t.getSemantics(button).getSemanticsData();
            expect(node.hasAction(SemanticsAction.tap), false);
            expect(find.text('正在提交…'), findsOneWidget);
            final frameWidget = find.byType(SuiteBusyFrame);
            expect(t.widget<SuiteBusyFrame>(frameWidget).busy, true);
            expect(
              InteractionScope.of(t.element(frameWidget)).reduceMotion,
              source != 'pointer',
            );
            await t.tap(button, warnIfMissed: false);
            await t.pump();
            expect(port.answers.length, 1);
            port.answers.single.complete(result);
            await frame(t);
            expect(t.widget<SuiteBusyFrame>(frameWidget).busy, false);
            expect(find.text('正在提交…'), findsNothing);
            expect(
              find.textContaining(result ? '已提交桌面提醒卡' : '暂未显示提醒'),
              findsOneWidget,
            );
            expect(
              t
                  .getSemantics(button)
                  .getSemanticsData()
                  .hasAction(SemanticsAction.tap),
              true,
            );
            await t.pumpWidget(const SizedBox());
            expect(port.clears, greaterThan(0));
            handle.dispose();
          },
        );
      }
    }
    testWidgets(
      '$suite held row and rapid pointer keep feedback without optimistic value',
      (t) async {
        final handle = t.ensureSemantics();
        final held = Completer<bool>();
        var calls = 0;
        await mount(
          t,
          NotificationToggleRow(
            settingKey: rowKey,
            value: false,
            enabled: true,
            titleKey: 'settings.notification.local.enabled',
            descriptionKey: 'settings.notification.local.enabledDescription',
            onChanged: (_) {
              calls++;
              return held.future;
            },
          ),
          suite,
        );
        for (var i = 0; i < 3; i++) {
          await t.tapAt(t.getCenter(find.byKey(rowKey)));
          await t.pump();
          expect(
            t
                .getSemantics(find.byKey(rowKey))
                .getSemanticsData()
                .flagsCollection
                .isToggled,
            Tristate.isFalse,
          );
          expect(t.hasRunningAnimations, true);
          await t.pump(const Duration(milliseconds: 30));
        }
        expect(calls, 3);
        held.complete(false);
        await frame(t);
        expect(
          t
              .getSemantics(find.byKey(rowKey))
              .getSemanticsData()
              .flagsCollection
              .isToggled,
          Tristate.isFalse,
        );
        await t.pumpWidget(const SizedBox());
        handle.dispose();
      },
    );
    testWidgets('$suite disabled rows and choices expose no reader action', (
      t,
    ) async {
      final handle = t.ensureSemantics();
      var calls = 0;
      await mount(
        t,
        SingleChildScrollView(
          child: Column(
            children: [
              NotificationToggleRow(
                settingKey: rowKey,
                value: true,
                enabled: false,
                titleKey: 'settings.notification.local.enabled',
                descriptionKey:
                    'settings.notification.local.enabledDescription',
                onChanged: (_) async {
                  calls++;
                  return true;
                },
              ),
              NotificationPreviewPanel(
                settings: InMemoryNotificationSettingsAdapter.forReview()
                    .current
                    .settings!,
                enabled: false,
                onSave: (_) async {
                  calls++;
                  return true;
                },
              ),
            ],
          ),
        ),
        suite,
      );
      for (final key in [
        rowKey,
        const Key('notification-preview-hiddenDetails'),
      ]) {
        final target = find.byKey(key);
        await t.ensureVisible(target);
        expect(
          t
              .getSemantics(target)
              .getSemanticsData()
              .hasAction(SemanticsAction.tap),
          false,
        );
        await t.tap(target, warnIfMissed: false);
        await t.pump();
      }
      expect(calls, 0);
      await t.pumpWidget(const SizedBox());
      handle.dispose();
    });
    for (final failure in ['refused', 'exception']) {
      testWidgets(
        '$suite desktop diagnostics $failure stays retryable without fallback',
        (t) async {
          final port = Diagnostics();
          await mount(
            t,
            DesktopNotificationTestButton(port: port, enabled: true),
            suite,
          );
          await t.tap(find.byKey(desktopKey));
          await frame(t);
          if (failure == 'exception') {
            port.diagnosticAnswers.single.completeError(
              StateError('synthetic failure'),
            );
          } else {
            port.diagnosticAnswers.single.complete(
              const DesktopNotificationTestResult(false, 'doNotDisturb'),
            );
          }
          await frame(t);
          expect(port.answers, isEmpty);
          expect(
            find.textContaining(
              failure == 'exception' ? '暂未显示提醒' : 'Windows 免打扰已开启',
            ),
            findsOneWidget,
          );
          expect(
            t.widget<SuiteBusyFrame>(find.byType(SuiteBusyFrame)).busy,
            false,
          );
          await t.tap(find.byKey(desktopKey));
          await frame(t);
          expect(port.diagnosticAnswers.length, 2);
          port.diagnosticAnswers.last.complete(
            const DesktopNotificationTestResult(true, 'submitted'),
          );
          await frame(t);
          expect(find.textContaining('已提交桌面提醒卡'), findsOneWidget);
          expect(t.takeException(), isNull);
          await t.pumpWidget(const SizedBox());
        },
      );
    }
    for (final phase in ['busy', 'complete']) {
      testWidgets(
        '$suite retire $phase feedback on port change and late answer',
        (t) async {
          final old = Port(), next = Port();
          var current = old;
          late StateSetter update;
          final live = await mount(
            t,
            StatefulBuilder(
              builder: (_, setState) {
                update = setState;
                return DesktopNotificationTestButton(
                  port: current,
                  enabled: true,
                );
              },
            ),
            suite,
          );
          await t.tap(find.byKey(desktopKey));
          await frame(t);
          final paintedState = t.state(find.byType(SuiteBusyFrame));
          if (phase == 'complete') {
            old.answers.single.complete(true);
            await frame(t);
          }
          update(() => current = next);
          await frame(t);
          expect(
            t.state(find.byType(SuiteBusyFrame)),
            isNot(same(paintedState)),
          );
          expect(find.textContaining('已提交桌面提醒卡'), findsNothing);
          await t.tap(find.byKey(desktopKey));
          await frame(t);
          if (phase == 'busy') {
            old.answers.single.complete(true);
            await frame(t);
          }
          expect(
            t.widget<SuiteBusyFrame>(find.byType(SuiteBusyFrame)).busy,
            true,
          );
          expect(find.textContaining('已提交桌面提醒卡'), findsNothing);
          live.change(() => live.reduce = true);
          await frame(t);
          expect(
            InteractionScope.of(t.element(find.byType(SuiteBusyFrame)))
                .reduceMotion,
            true,
          );
          next.answers.single.complete(false);
          await frame(t);
          expect(find.textContaining('暂未显示提醒'), findsOneWidget);
          await t.pumpWidget(const SizedBox());
        },
      );
    }
    testWidgets(
      '$suite actual notification editor stages then failed save and retry',
      (t) async {
        final handle = t.ensureSemantics();
        final port = CountingPort();
        final module = createNotificationSettingsModule(port);
        addTearDown(module.dispose);
        await module.initialize();
        await mount(t, NotificationSettingsPage(module: module), suite);
        final windows = find.byKey(const Key('notification-channel-windows'));
        final initial =
            port.inner.current.settings!.channels.windowsDesktopEnabled;
        await activate(t, windows, 'reader');
        await frame(t);
        final preview = find.byKey(
          const Key('notification-preview-hiddenDetails'),
        );
        await activate(t, preview, 'reader');
        await frame(t);
        expect(port.writes, 0);
        expect(port.inner.current.revision, 11);
        expect(
          port.inner.current.settings!.channels.windowsDesktopEnabled,
          initial,
        );
        port.inner.failNextUpdate = true;
        await activate(t, find.byKey(const Key('notification-save')), 'reader');
        await t.pumpAndSettle();
        expect(port.writes, 1);
        expect(port.inner.current.revision, 11);
        await activate(t, find.byKey(const Key('notification-save')), 'reader');
        await t.pumpAndSettle();
        expect(port.writes, 2);
        expect(port.inner.current.revision, 12);
        expect(
          port.inner.current.settings!.channels.windowsDesktopEnabled,
          !initial,
        );
        expect(
          port.inner.current.settings!.previewMode,
          NotificationPreviewMode.hiddenDetails,
        );
        await t.pumpWidget(const SizedBox());
        handle.dispose();
      },
    );
    testWidgets(
      '$suite disable then reenable ignores pending result and dispose clears',
      (t) async {
        final port = Port();
        var enabled = true;
        late StateSetter update;
        await mount(
          t,
          StatefulBuilder(
            builder: (_, setState) {
              update = setState;
              return DesktopNotificationTestButton(
                port: port,
                enabled: enabled,
              );
            },
          ),
          suite,
        );
        await t.tap(find.byKey(desktopKey));
        await frame(t);
        update(() => enabled = false);
        await frame(t);
        expect(find.text('正在提交…'), findsNothing);
        port.answers.single.complete(true);
        await frame(t);
        expect(find.textContaining('已提交桌面提醒卡'), findsNothing);
        update(() => enabled = true);
        await frame(t);
        await t.tap(find.byKey(desktopKey));
        await frame(t);
        expect(port.answers.length, 2);
        await t.pumpWidget(const SizedBox());
        port.answers.last.complete(true);
        await t.pump();
        expect(port.clears, greaterThan(0));
        expect(t.takeException(), isNull);
      },
    );
  }
  for (final suite in InteractionSuite.values) {
    for (final locale in [
      const Locale('zh', 'CN'),
      const Locale('zh', 'TW'),
      const Locale('en', 'US'),
    ]) {
      testWidgets('$suite desktop busy fits narrow two-times text $locale', (
        t,
      ) async {
        final port = Port();
        await mount(
          t,
          Builder(
            builder: (context) => Localizations.override(
              context: context,
              locale: locale,
              child: DesktopNotificationTestButton(port: port, enabled: true),
            ),
          ),
          suite,
          width: 250,
          scale: 2,
        );
        await t.pumpAndSettle();
        await t.tap(find.byKey(desktopKey));
        await frame(t);
        final label = t.widget<SuiteBusyLabel>(find.byType(SuiteBusyLabel));
        expect(
          label.text,
          locale.languageCode == 'en' ? 'Submitting…' : '正在提交…',
        );
        expect(t.takeException(), isNull);
        port.answers.single.complete(false);
        await frame(t);
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
      });
    }
  }
  for (final suite in [
    InteractionSuite.rail,
    InteractionSuite.scan,
    InteractionSuite.glow,
  ]) {
    testWidgets('$suite combined notification controls frames review', (
      t,
    ) async {
      final capture = GlobalKey();
      final port = Port();
      var value = false;
      late StateSetter update;
      final live = await mount(
        t,
        StatefulBuilder(
          builder: (context, setState) {
            update = setState;
            return SingleChildScrollView(
              child: Column(
                children: [
                  NotificationToggleRow(
                    settingKey: rowKey,
                    value: value,
                    enabled: true,
                    titleKey: 'settings.notification.local.enabled',
                    descriptionKey:
                        'settings.notification.local.enabledDescription',
                    onChanged: (next) async {
                      update(() => value = next);
                      return true;
                    },
                  ),
                  NotificationPreviewPanel(
                    settings: InMemoryNotificationSettingsAdapter.forReview()
                        .current
                        .settings!,
                    enabled: true,
                    onSave: (_) async => true,
                  ),
                  DesktopNotificationTestButton(port: port, enabled: true),
                ],
              ),
            );
          },
        ),
        suite,
        width: 820,
        capture: capture,
      );
      await t.tapAt(t.getCenter(find.byKey(rowKey)));
      await t.pump();
      await t.pump(const Duration(milliseconds: 80));
      Future<void> save(String phase) async {
        await t.pump();
        await t.runAsync(() async {
          final image =
              await (capture.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary)
                  .toImage();
          final bytes = await image.toByteData(format: ImageByteFormat.png);
          final dir = Directory('build/reviews/interaction-batch3ay');
          await dir.create(recursive: true);
          await File('${dir.path}/${suite.name}-$phase.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }

      await save('active');
      await t.tap(find.byKey(desktopKey));
      await frame(t);
      await t.pump(const Duration(milliseconds: 150));
      await save('busy');
      port.answers.single.complete(true);
      await frame(t);
      await t.pump(const Duration(milliseconds: 80));
      await save('complete');
      live.change(() => live.light = true);
      await frame(t);
      await t.pump(const Duration(seconds: 2));
      await save('light');
      await t.pumpWidget(const SizedBox());
    });
  }
}
