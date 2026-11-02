import 'dart:async';
import 'dart:ui' show SemanticsAction, Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/app/routing/open_destination_intent.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_action_button.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_activation_origin.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_dialog.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_page_route.dart';
import 'package:starbridge_flutter/features/settings/about_legal_settings_page.dart';
import 'package:starbridge_flutter/features/settings/general_settings_sections.dart';
import 'package:starbridge_flutter/features/settings/settings_entry_dialog.dart';
import 'package:starbridge_flutter/features/settings/settings_models.dart';
import 'package:starbridge_flutter/features/settings/settings_page.dart';

import 'interaction_batch3do_test.dart'
    show exposedNodes, loadFonts, scopedApp, size;

const _timeout = Timeout(Duration(seconds: 45));
const _pageKey = Key('settings-real-page');
InteractionSource _source(String input) =>
    input == 'pointer' ? InteractionSource.pointer : InteractionSource.keyboard;
Finder _row(SettingsSection section) =>
    find.byKey(Key('settings-section-${section.name}'));
Finder _body(SettingsSection section) =>
    find.byKey(Key('settings-real-body-${section.name}'));

Future<void> _frames(WidgetTester t, [int count = 3]) async {
  for (var i = 0; i < count; i++) {
    await t.pump();
  }
}

Future<void> _tail(WidgetTester t) async {
  for (var i = 0; i < 8; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _withSemantics(
  WidgetTester t,
  Future<void> Function() body,
) async {
  final handle = t.ensureSemantics();
  try {
    await body();
  } finally {
    handle.dispose();
  }
}

Future<void> _focusByTab(WidgetTester t, Finder target) async {
  final widget = t.widget(target);
  final focus = switch (widget) {
    SuitePressable value => value.focusNode!,
    ButtonStyleButton value => value.focusNode!,
    IconButton value => value.focusNode!,
    _ => throw StateError('Not a public keyboard owner: $widget'),
  };
  var tabs = 0;
  while (!focus.hasPrimaryFocus && tabs < 64) {
    await t.sendKeyEvent(LogicalKeyboardKey.tab);
    await _frames(t, 2);
    tabs++;
  }
  expect(focus.canRequestFocus, isTrue);
  expect(FocusManager.instance.primaryFocus, same(focus));
}

/// Real input only: no requestFocus, onActivate call, or State._select access.
Future<void> _act(WidgetTester t, Finder target, String input) async {
  expect(target, findsOneWidget);
  await t.ensureVisible(target);
  await _tail(t);
  if (input == 'pointer') {
    await t.tap(target);
  } else if (input == 'keyboard') {
    await _focusByTab(t, target);
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
  } else {
    final label = switch (t.widget(target)) {
      SuitePressable value =>
        value.semanticLabel ?? t.getSemantics(target).getSemanticsData().label,
      _ => t.getSemantics(target).getSemanticsData().label,
    };
    final nodes = exposedNodes(t)
        .where(
          (node) =>
              node.getSemanticsData().label == label &&
              node.getSemanticsData().hasAction(SemanticsAction.tap),
        )
        .toList();
    expect(nodes, hasLength(1));
    t.binding.renderViews.single.owner!.semanticsOwner!.performAction(
      nodes.single.id,
      SemanticsAction.tap,
    );
  }
  await _frames(t);
}

/// The Page's documented async leave-guard seam. It deliberately does not
/// model privacy/notification persistence, which has separate owner tests.
class _Gate {
  final entered = <InteractionSource>[];
  final returned = <InteractionSource>[];
  final waiting = <Completer<bool>>[];
  Future<bool> ask(BuildContext context) async {
    entered.add(currentStarBridgeActivationSource);
    final gate = Completer<bool>();
    waiting.add(gate);
    final allowed = await gate.future;
    returned.add(currentStarBridgeActivationSource);
    return allowed;
  }

  void answer(bool value) {
    waiting.firstWhere((gate) => !gate.isCompleted).complete(value);
  }

  void release() {
    for (final gate in waiting) {
      if (!gate.isCompleted) {
        gate.complete(false);
      }
    }
  }
}

class _DialogGate {
  final entered = <InteractionSource>[];
  final returned = <InteractionSource>[];
  StarBridgeDialogRoute<bool>? route;
  Future<bool> ask(BuildContext context) async {
    entered.add(currentStarBridgeActivationSource);
    final answer = await showStarBridgeDialog<bool>(
      context,
      source: currentStarBridgeActivationSource,
      barrierDismissible: false,
      onRouteCreated: (value) => route = value,
      builder: (dialogContext) => AlertDialog(
        key: const Key('settings-real-guard-dialog'),
        title: const Text('A pending settings decision'),
        content: const Text('The original destination remains selected.'),
        actions: [
          for (final entry in <(String, bool?)>[
            ('cancel', null),
            ('stay', false),
            ('allow', true),
          ])
            StarBridgeActionButton(
              controlKey: Key('settings-real-guard-${entry.$1}'),
              semanticLabel: 'settings decision ${entry.$1}',
              onActivate: (source) => dismissStarBridgeDialog<bool>(
                dialogContext,
                source: source,
                result: entry.$2,
              ),
              child: Text(entry.$1),
            ),
        ],
      ),
    );
    returned.add(currentStarBridgeActivationSource);
    return answer ?? false;
  }
}

class _Probe {
  _Probe(this.suite, this.initial);
  InteractionSuite suite;
  final SettingsSection initial;
  final privacy = _Gate(), notifications = _Gate();
  final built = <SettingsSection>[];
  final openingFacts = <SettingsSection, InteractionSource>{};
  _DialogGate? dialog;
  bool visible = true, reduce = false, light = false, opened = true;
  InteractionSource? opening;
  late StateSetter update;
  _Gate get active =>
      initial == SettingsSection.syncPrivacy ? privacy : notifications;
  _Gate get inactive =>
      initial == SettingsSection.syncPrivacy ? notifications : privacy;
  Widget content(SettingsSection section) {
    built.add(section);
    // The actual content Widget is below the Page's opening scope; its
    // delegate's incoming context intentionally is not used to infer a fact.
    return Builder(
      builder: (context) {
        openingFacts[section] = resolveStarBridgeInitialReadSource(
          context,
          InteractionSource.programmatic,
        );
        return Center(
          child: Text(
            'settings content ${section.name}',
            key: Key('settings-real-body-${section.name}'),
          ),
        );
      },
    );
  }

  Future<bool> guard(BuildContext context, _Gate gate) =>
      identical(gate, active) && dialog != null
      ? dialog!.ask(context)
      : gate.ask(context);

  Widget app() => StatefulBuilder(
    builder: (_, setter) {
      update = setter;
      return scopedApp(
        Builder(
          builder: (context) {
            if (!opened) {
              return StarBridgeActionButton(
                controlKey: const Key('settings-real-open'),
                onActivate: (source) => update(() {
                  opening = source;
                  opened = true;
                }),
                child: const Text('Open actual settings'),
              );
            }
            final page = visible
                ? SettingsPage(
                    key: _pageKey,
                    initialSection: initial,
                    accountAndIdentityBuilder: (_) =>
                        content(SettingsSection.accountIdentity),
                    generalDataBuilder: (_) =>
                        content(SettingsSection.generalData),
                    syncPrivacyBuilder: (_) =>
                        content(SettingsSection.syncPrivacy),
                    notificationsBuilder: (_) =>
                        content(SettingsSection.notifications),
                    diagnosticsBuilder: (_) =>
                        content(SettingsSection.diagnostics),
                    helpSupportBuilder: (_) =>
                        content(SettingsSection.aboutLegal),
                    confirmPrivacyLeave: (context) => guard(context, privacy),
                    confirmNotificationsLeave: (context) =>
                        guard(context, notifications),
                  )
                : const Text('settings departed');
            return opening == null
                ? page
                : starBridgeInitialReadViewport(
                    context,
                    source: opening!,
                    child: page,
                  );
          },
        ),
        suite,
        reduce: reduce,
        light: light,
      );
    },
  );
}

SuiteSideNav _nav(WidgetTester t) =>
    t.widget<SuiteSideNav>(find.byType(SuiteSideNav));

void _selected(WidgetTester t, SettingsSection section) {
  expect(_body(section), findsOneWidget);
  expect(_nav(t).selectedId, section.name);
  for (final item in visibleSettingsSections) {
    final pressable = t.widget<SuitePressable>(_row(item));
    expect(pressable.kind, PressableKind.navItem);
    expect(pressable.semanticSelected, item == section);
    expect(
      pressable.semanticLabel,
      AppStrings.of(t.element(_row(item))).text(item.labelKey),
    );
    expect(pressable.excludeChildSemantics, isTrue);
  }
}

Future<_Probe> _mount(
  WidgetTester t,
  InteractionSuite suite,
  SettingsSection initial, {
  bool dialog = false,
  double width = 1280,
}) async {
  size(t, Size(width, 1000));
  final p = _Probe(suite, initial);
  if (dialog) {
    p.dialog = _DialogGate();
  }
  await t.pumpWidget(p.app());
  await _frames(t);
  await _tail(t);
  _selected(t, initial);
  expect(t.getSize(find.byType(SuiteSideNav)).width, width < 960 ? 196 : 276);
  expect(find.byKey(const Key('settings-section-picker')), findsNothing);
  return p;
}

Future<void> _close(WidgetTester t, _Probe p) async {
  p.privacy.release();
  p.notifications.release();
  await _frames(t);
  await t.pumpWidget(const SizedBox.shrink());
  await _frames(t);
  expect(t.takeException(), isNull);
}

void main() {
  setUpAll(loadFonts);
  for (final suite in InteractionSuite.values) {
    for (final initial in [
      SettingsSection.syncPrivacy,
      SettingsSection.notifications,
    ]) {
      for (final input in ['pointer', 'keyboard', 'reader']) {
        testWidgets(
          '$suite $initial $input awaits guard and rejects duplicates',
          (t) => _withSemantics(t, () async {
            final p = await _mount(t, suite, initial);
            final state = t.state(find.byKey(_pageKey));
            final originalSource = _nav(t).changeSource;
            final originalFact = p.openingFacts[initial];
            await _act(t, _row(SettingsSection.generalData), input);
            expect(p.active.entered, [_source(input)]);
            expect(p.inactive.entered, isEmpty);
            expect(p.active.returned, isEmpty);
            expect(p.built, isNot(contains(SettingsSection.generalData)));
            _selected(t, initial);
            expect(_nav(t).changeSource, originalSource);
            expect(p.openingFacts[initial], originalFact);
            // Every actual request is delivered; the original Page admission
            // guard, not a test lock, suppresses concurrent destination changes.
            await _act(t, _row(SettingsSection.accountIdentity), 'pointer');
            await _act(t, _row(SettingsSection.aboutLegal), 'keyboard');
            expect(p.active.entered, [_source(input)]);
            expect(p.built, isNot(contains(SettingsSection.accountIdentity)));
            expect(p.built, isNot(contains(SettingsSection.aboutLegal)));
            p.update(() {
              p.reduce = true;
              p.light = true;
              p.suite = suite == InteractionSuite.scan
                  ? InteractionSuite.glow
                  : InteractionSuite.scan;
            });
            await _frames(t);
            _selected(t, initial);
            final scope = InteractionScope.of(t.element(_row(initial)));
            expect(scope.reduceMotion, isTrue);
            expect(scope.palette.brightness, Brightness.light);
            expect(scope.suite, p.suite);
            expect(t.state(find.byKey(_pageKey)), same(state));
            expect(p.openingFacts[initial], originalFact);
            p.active.answer(false);
            await _frames(t, 5);
            expect(p.active.returned, [_source(input)]);
            _selected(t, initial);
            expect(p.built, isNot(contains(SettingsSection.generalData)));
            final next = input == 'pointer' ? 'keyboard' : 'pointer';
            p.update(() => p.reduce = false);
            await _frames(t);
            await _act(t, _row(SettingsSection.generalData), next);
            _selected(t, initial);
            expect(p.active.entered, [_source(input), _source(next)]);
            p.active.answer(true);
            await _frames(t, 5);
            _selected(t, SettingsSection.generalData);
            expect(_nav(t).changeSource, _source(next));
            expect(p.openingFacts[SettingsSection.generalData], _source(next));
            expect(p.active.returned, [_source(input), _source(next)]);
            expect(p.inactive.entered, isEmpty);
            expect(t.state(find.byKey(_pageKey)), same(state));
            final calls = p.active.entered.length;
            await _act(t, _row(SettingsSection.generalData), input);
            expect(p.active.entered.length, calls);
            _selected(t, SettingsSection.generalData);
            expect(
              t
                  .getSemantics(_row(SettingsSection.generalData))
                  .getSemanticsData()
                  .flagsCollection
                  .isSelected,
              Tristate.isTrue,
            );
            final following = next == 'pointer' ? 'keyboard' : 'pointer';
            await _act(t, _row(SettingsSection.accountIdentity), following);
            _selected(t, SettingsSection.accountIdentity);
            expect(
              p.openingFacts[SettingsSection.accountIdentity],
              _source(following),
            );
            expect(_nav(t).changeSource, _source(following));
            expect(p.active.entered.length, calls);
            await _close(t, p);
          }),
          timeout: _timeout,
        );
      }

      testWidgets(
        '$suite $initial real dialog cancel/stay/allow source bridge',
        (t) => _withSemantics(t, () async {
          final p = await _mount(t, suite, initial, dialog: true);
          final guard = p.dialog!;
          await _act(t, _row(SettingsSection.generalData), 'pointer');
          expect(
            find.byKey(const Key('settings-real-guard-dialog')),
            findsOneWidget,
          );
          expect(guard.route!.instant, isFalse);
          _selected(t, initial);
          await _act(
            t,
            find.byKey(const Key('settings-real-guard-cancel')),
            'reader',
          );
          await _tail(t);
          expect(guard.returned, [InteractionSource.keyboard]);
          _selected(t, initial);
          expect(p.built, isNot(contains(SettingsSection.generalData)));

          await _act(t, _row(SettingsSection.generalData), 'pointer');
          await _act(
            t,
            find.byKey(const Key('settings-real-guard-stay')),
            'keyboard',
          );
          await _tail(t);
          _selected(t, initial);
          expect(p.built, isNot(contains(SettingsSection.generalData)));

          await _act(t, _row(SettingsSection.generalData), 'keyboard');
          expect(guard.route!.instant, isTrue);
          p.update(() {
            p.reduce = true;
            p.light = true;
            p.suite = suite == InteractionSuite.glow
                ? InteractionSuite.scan
                : InteractionSuite.glow;
          });
          await _frames(t, 2);
          final scope = InteractionScope.of(
            t.element(find.byKey(const Key('settings-real-guard-dialog'))),
          );
          expect(scope.reduceMotion, isTrue);
          expect(scope.palette.brightness, Brightness.light);
          expect(scope.suite, p.suite);
          _selected(t, initial);
          await _act(
            t,
            find.byKey(const Key('settings-real-guard-allow')),
            'pointer',
          );
          await _tail(t);
          _selected(t, SettingsSection.generalData);
          expect(_nav(t).changeSource, InteractionSource.pointer);
          expect(
            p.openingFacts[SettingsSection.generalData],
            InteractionSource.pointer,
          );
          expect(guard.entered, [
            InteractionSource.pointer,
            InteractionSource.pointer,
            InteractionSource.keyboard,
          ]);
          expect(guard.returned, [
            InteractionSource.keyboard,
            InteractionSource.keyboard,
            InteractionSource.pointer,
          ]);
          expect(p.inactive.entered, isEmpty);
          expect(
            find.byKey(const Key('settings-real-guard-dialog')),
            findsNothing,
          );
          await _close(t, p);
        }),
        timeout: _timeout,
      );

      testWidgets(
        '$suite $initial departure cannot revive approved destination',
        (t) async {
          final p = await _mount(t, suite, initial);
          await _act(t, _row(SettingsSection.generalData), 'keyboard');
          expect(p.active.entered, [InteractionSource.keyboard]);
          _selected(t, initial);
          p.update(() => p.visible = false);
          await _frames(t, 4);
          expect(find.byType(SettingsPage), findsNothing);
          p.active.answer(true);
          await _frames(t, 5);
          await _tail(t);
          expect(p.active.returned, [InteractionSource.keyboard]);
          expect(p.built, isNot(contains(SettingsSection.generalData)));
          expect(find.byType(SettingsPage), findsNothing);
          expect(find.text('settings departed'), findsOneWidget);
          await _close(t, p);
        },
        timeout: _timeout,
      );
    }

    testWidgets('$suite compact rail real arrow traversal stays bounded', (
      t,
    ) async {
      final p = await _mount(
        t,
        suite,
        SettingsSection.accountIdentity,
        width: 820,
      );
      final account = _row(SettingsSection.accountIdentity);
      await _focusByTab(t, account);
      await t.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await _frames(t);
      _selected(t, SettingsSection.accountIdentity);
      await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await _frames(t);
      _selected(t, SettingsSection.generalData);
      expect(_nav(t).changeSource, InteractionSource.keyboard);
      expect(
        t
            .widget<SuitePressable>(_row(SettingsSection.generalData))
            .focusNode!
            .hasPrimaryFocus,
        isTrue,
      );
      await t.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await _frames(t);
      _selected(t, SettingsSection.accountIdentity);
      await _act(t, _row(SettingsSection.aboutLegal), 'keyboard');
      _selected(t, SettingsSection.aboutLegal);
      await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await _frames(t);
      _selected(t, SettingsSection.aboutLegal);
      expect(p.privacy.entered, isEmpty);
      expect(p.notifications.entered, isEmpty);
      expect(t.getSize(find.byType(SuiteSideNav)).width, 196);
      for (final section in visibleSettingsSections) {
        expect(
          find.text(
            AppStrings.of(t.element(_row(section)))
                .text(section.descriptionKey),
          ),
          findsNothing,
        );
      }
      await _close(t, p);
    }, timeout: _timeout);

    testWidgets(
      '$suite initial keyboard opening fact reaches actual child',
      (t) => _withSemantics(t, () async {
        size(t, const Size(1280, 1000));
        final p = _Probe(suite, SettingsSection.accountIdentity)
          ..opened = false;
        await t.pumpWidget(p.app());
        await _frames(t);
        expect(find.byType(SettingsPage), findsNothing);
        await _act(t, find.byKey(const Key('settings-real-open')), 'keyboard');
        _selected(t, SettingsSection.accountIdentity);
        expect(_nav(t).changeSource, InteractionSource.keyboard);
        expect(
          p.openingFacts[SettingsSection.accountIdentity],
          InteractionSource.keyboard,
        );
        await _act(t, _row(SettingsSection.generalData), 'pointer');
        _selected(t, SettingsSection.generalData);
        expect(_nav(t).changeSource, InteractionSource.pointer);
        expect(
          p.openingFacts[SettingsSection.generalData],
          InteractionSource.pointer,
        );
        await _act(t, _row(SettingsSection.syncPrivacy), 'reader');
        _selected(t, SettingsSection.syncPrivacy);
        expect(_nav(t).changeSource, InteractionSource.keyboard);
        expect(
          p.openingFacts[SettingsSection.syncPrivacy],
          InteractionSource.keyboard,
        );
        expect(p.privacy.entered, isEmpty);
        expect(p.notifications.entered, isEmpty);
        await _close(t, p);
      }),
      timeout: _timeout,
    );

    for (final input in ['pointer', 'keyboard', 'reader']) {
      testWidgets(
        '$suite $input overlay shortcut obeys actual Actions gate',
        (t) => _withSemantics(t, () async {
          size(t, const Size(1280, 1000));
          var available = false;
          final invoked = <(String, InteractionSource)>[];
          late StateSetter update;
          await t.pumpWidget(
            StatefulBuilder(
              builder: (_, setter) {
                update = setter;
                const content = SingleChildScrollView(
                  child: GeneralSettingsDataSections(),
                );
                return scopedApp(
                  available
                      ? Actions(
                          actions: {
                            OpenDestinationIntent:
                                CallbackAction<OpenDestinationIntent>(
                                  onInvoke: (intent) {
                                    invoked.add((
                                      intent.route,
                                      currentStarBridgeActivationSource,
                                    ));
                                    return null;
                                  },
                                ),
                          },
                          child: content,
                        )
                      : content,
                  suite,
                );
              },
            ),
          );
          await _frames(t);
          final overlay = find.byKey(const Key('general-overlay-settings'));
          await t.ensureVisible(overlay);
          await _tail(t);
          final owner = find.ancestor(
            of: overlay,
            matching: find.byType(StarBridgeActionButton),
          );
          expect(owner, findsOneWidget);
          expect(t.widget<StarBridgeActionButton>(owner).onActivate, isNull);
          expect(
            t
                .getSemantics(overlay)
                .getSemanticsData()
                .hasAction(SemanticsAction.tap),
            isFalse,
          );
          // This deliberate disabled physical press does not invent an action
          // for keyboard/reader users whose real exposed action is absent.
          await t.tapAt(t.getCenter(overlay));
          await _frames(t);
          expect(invoked, isEmpty);
          update(() => available = true);
          await _frames(t);
          await _act(t, overlay, input);
          expect(invoked, [('/overlay', _source(input))]);
          expect(find.byType(GeneralSettingsDataSections), findsOneWidget);
          update(() => available = false);
          await _frames(t);
          expect(
            t
                .widget<StarBridgeActionButton>(
                  find.ancestor(
                    of: overlay,
                    matching: find.byType(StarBridgeActionButton),
                  ),
                )
                .onActivate,
            isNull,
          );
          expect(
            t
                .getSemantics(overlay)
                .getSemanticsData()
                .hasAction(SemanticsAction.tap),
            isFalse,
          );
          await t.tapAt(t.getCenter(overlay));
          await _frames(t);
          expect(invoked.length, 1);
          await t.pumpWidget(const SizedBox.shrink());
          await _frames(t);
          expect(t.takeException(), isNull);
        }),
        timeout: _timeout,
      );

      testWidgets(
        '$suite $input About route keeps overrides and original return',
        (t) => _withSemantics(t, () async {
          size(t, const Size(1280, 1000));
          final versionOrigins = <InteractionSource>[];
          final observedOverrides = <Map<String, SettingsEntryOpener>>[];
          late final Map<String, SettingsEntryOpener> openers;
          openers = {
            'client-version': (context) async {
              versionOrigins.add(currentStarBridgeActivationSource);
              observedOverrides.add(SettingsEntryOverrides.of(context));
            },
          };
          await t.pumpWidget(
            scopedApp(
              SettingsEntryOverrides(
                openers: openers,
                child: const SingleChildScrollView(
                  child: GeneralSettingsDataSections(),
                ),
              ),
              suite,
            ),
          );
          await _frames(t);
          final original = t.element(find.byType(SingleChildScrollView));
          await _act(
            t,
            find.byKey(const Key('general-about-application')),
            input,
          );
          final about = find.byType(AboutLegalSettingsPage);
          expect(about, findsOneWidget);
          final route = ModalRoute.of(t.element(about));
          expect(route, isA<StarBridgePageRoute<void>>());
          final actual = route! as StarBridgePageRoute<void>;
          expect(actual.instant, input != 'pointer');
          if (input != 'pointer') {
            expect(actual.transitionDuration, Duration.zero);
            expect(actual.animation!.value, 1);
            expect(actual.animation!.isAnimating, isFalse);
          }
          await _tail(t);
          expect(actual.isCurrent, isTrue);
          expect(SettingsEntryOverrides.of(t.element(about)), same(openers));
          expect(
            find.byKey(const Key('settings-about-app-icon')),
            findsOneWidget,
          );
          expect(
            find.byKey(const Key('settings-cig-fankit-notice')),
            findsOneWidget,
          );
          expect(versionOrigins, isEmpty);
          final version = find.descendant(
            of: about,
            matching: find.byKey(const Key('client-version-open')),
          );
          await _act(t, version, input);
          expect(versionOrigins, [_source(input)]);
          expect(observedOverrides, hasLength(1));
          expect(observedOverrides.single, same(openers));
          expect(actual.isCurrent, isTrue);
          await _act(t, find.byKey(const Key('general-about-back')), input);
          await _tail(t);
          expect(find.byType(AboutLegalSettingsPage), findsNothing);
          expect(find.byType(GeneralSettingsDataSections), findsOneWidget);
          expect(t.element(find.byType(SingleChildScrollView)), same(original));
          expect(
            SettingsEntryOverrides.of(
              t.element(find.byType(GeneralSettingsDataSections)),
            ),
            same(openers),
          );
          expect(versionOrigins.length, 1);
          await t.pumpWidget(const SizedBox.shrink());
          await _frames(t);
          expect(t.takeException(), isNull);
        }),
        timeout: _timeout,
      );
    }
  }
}
