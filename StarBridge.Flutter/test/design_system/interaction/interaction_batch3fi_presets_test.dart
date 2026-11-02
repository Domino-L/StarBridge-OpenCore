import 'dart:async';
import 'dart:ui' show SemanticsAction;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_action_button.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_activation_origin.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_dialog.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_expansion_tile.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_field_frame.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_preset_import_preview.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_preset_settings_dialog.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_preset_transfer.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_workspace_models.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_workspace_module.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_workspace_page.dart';

import '../../features/overlay_settings/overlay_settings_ux_a_test.dart'
    show settings;
import '../../features/overlay_settings/overlay_preset_transfer_test.dart'
    show layout;
import 'interaction_batch3do_test.dart'
    show exposedNodes, loadFonts, scopedApp, size;
import 'interaction_batch3o_test.dart' as original show Port;

const _timeout = Timeout(Duration(seconds: 45));
InteractionSource _source(String input) =>
    input == 'pointer' ? InteractionSource.pointer : InteractionSource.keyboard;

class _Port extends original.Port {
  final admissions = <(OverlayWorkspaceMutation, int, InteractionSource)>[];
  @override
  Future<OverlayWorkspaceWriteResult> apply(
    OverlayWorkspaceMutation mutation, {
    required int expectedRevision,
  }) {
    admissions.add((
      mutation,
      expectedRevision,
      currentStarBridgeActivationSource,
    ));
    return super.apply(mutation, expectedRevision: expectedRevision);
  }
}

class _Live {
  _Live(this.module, this.suite, {this.page = false});
  final OverlayWorkspaceModule module;
  InteractionSuite suite;
  final bool page;
  bool reduce = false, light = false;
  late StateSetter update;
  final decisions = <bool?>[];
  final confirmations = <InteractionSource>[];
  Widget app() => StatefulBuilder(
    builder: (_, setter) {
      update = setter;
      return scopedApp(
        page
            ? OverlayWorkspacePage(module: module)
            : Builder(
                builder: (context) => Wrap(
                  children: [
                    StarBridgeActionButton(
                      controlKey: const Key('preset-name-open'),
                      onActivate: (source) => showStarBridgeDialog<void>(
                        context,
                        source: source,
                        builder: (_) => OverlayPresetSettingsDialog(
                          module: module,
                          preset:
                              module.projection.value.snapshot!.presets.first,
                        ),
                      ),
                      child: const Text('Open original preset settings'),
                    ),
                    StarBridgeActionButton(
                      controlKey: const Key('preset-preview-open'),
                      onActivate: (source) async {
                        final result = await showStarBridgeDialog<bool>(
                          context,
                          source: source,
                          builder: (_) => OverlayPresetImportPreview(
                            name: 'Synthetic inspection',
                            settings: settings(),
                            currentSettings: module.projection.value.settings,
                            layout: layout,
                            onConfirmSource: confirmations.add,
                          ),
                        );
                        decisions.add(result);
                      },
                      child: const Text('Open original preset inspection'),
                    ),
                  ],
                ),
              ),
        suite,
        reduce: reduce,
        light: light,
      );
    },
  );
}

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

Future<void> _semantics(WidgetTester t, Future<void> Function() body) async {
  final handle = t.ensureSemantics();
  try {
    await body();
  } finally {
    handle.dispose();
  }
}

Finder _control(Finder target) {
  final owned = find.byWidgetPredicate(
    (w) => w is ButtonStyleButton || w is SuitePressable || w is IconButton,
  );
  final direct = target.evaluate().single.widget;
  return direct is ButtonStyleButton ||
          direct is SuitePressable ||
          direct is IconButton
      ? target
      : find.descendant(of: target, matching: owned).first;
}

Future<void> _act(WidgetTester t, Finder target, String input) async {
  expect(target, findsOneWidget);
  await t.ensureVisible(target);
  await _tail(t);
  final actual = _control(target);
  if (input == 'pointer') {
    await t.tap(actual);
  } else if (input == 'keyboard') {
    final focus = switch (t.widget(actual)) {
      SuitePressable w => w.focusNode!,
      ButtonStyleButton w => w.focusNode!,
      IconButton w => w.focusNode!,
      _ => throw StateError('No public input owner'),
    };
    var tabs = 0;
    while (!focus.hasPrimaryFocus && tabs < 96) {
      await t.sendKeyEvent(LogicalKeyboardKey.tab);
      await _frames(t, 2);
      tabs++;
    }
    expect(FocusManager.instance.primaryFocus, same(focus));
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
  } else {
    final label = t.getSemantics(actual).getSemanticsData().label;
    final nodes = exposedNodes(t)
        .where(
          (n) =>
              n.getSemanticsData().label == label &&
              n.getSemanticsData().hasAction(SemanticsAction.tap),
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

String _copy(WidgetTester t, String key) => AppStrings.of(
  t.element(
    find.byType(OverlayWorkspacePage).evaluate().isNotEmpty
        ? find.byType(OverlayWorkspacePage)
        : find.byType(AlertDialog).last,
  ),
).text(key);
Finder _button(String text) =>
    find.widgetWithText(StarBridgeActionButton, text).last;
Finder _name() => find.descendant(
  of: find.byType(OverlayPresetSettingsDialog),
  matching: find.byType(TextField),
);
Finder _editor(Finder field) =>
    find.descendant(of: field, matching: find.byType(EditableText));
Future<(_Port, OverlayWorkspaceModule, _Live)> _mount(
  WidgetTester t,
  InteractionSuite suite, {
  bool page = false,
}) async {
  size(t, const Size(1280, 1000));
  final port = _Port();
  final module = OverlayWorkspaceModule(port);
  await module.refresh();
  final live = _Live(module, suite, page: page);
  await t.pumpWidget(live.app());
  await _frames(t);
  await _tail(t);
  return (port, module, live);
}

Future<void> _close(WidgetTester t, OverlayWorkspaceModule module) async {
  await t.pumpWidget(const SizedBox.shrink());
  await _frames(t);
  module.dispose();
  expect(t.takeException(), isNull);
}

Future<void> _entry(
  WidgetTester t,
  String id,
  String input, {
  bool finish = true,
}) async {
  await _act(t, find.byKey(const Key('overlay-preset-manage')), input);
  await _tail(t);
  await _act(t, find.byKey(ValueKey<Object>('overlay-preset-$id')), input);
  if (finish) {
    await _tail(t);
  }
}

Future<void> _inspect(WidgetTester t, String text, String input) async {
  await _entry(t, 'import', input);
  final field = find.descendant(
    of: find.byType(AlertDialog),
    matching: find.byType(TextField),
  );
  await t.enterText(field, text);
  await _act(t, _button(_copy(t, 'overlay.importPreview.inspect')), input);
  await _tail(t);
}

void _staticSnack(WidgetTester t) {
  final snack = t.widget<SnackBar>(
    find.byWidgetPredicate((w) => w is SnackBar).last,
  );
  expect(snack.animation!.value, 1);
  expect(snack.animation!.isAnimating, isFalse);
}

void main() {
  setUpAll(loadFonts);
  testWidgets('scan preset inspection uses the approved shared disclosure', (
    t,
  ) async {
    size(t, const Size(1280, 1000));
    await t.pumpWidget(
      scopedApp(
        OverlayPresetImportPreview(
          name: 'Synthetic inspection',
          settings: settings(),
          currentSettings: settings(),
          layout: layout,
        ),
        InteractionSuite.scan,
      ),
    );
    await t.pump();
    expect(find.byType(StarBridgeExpansionTile), findsNWidgets(2));
    expect(find.byType(ExpansionTile), findsNothing);
    await t.pumpWidget(const SizedBox.shrink());
  }, timeout: const Timeout(Duration(seconds: 45)));

  for (final suite in InteractionSuite.values) {
    for (final input in ['pointer', 'keyboard', 'reader']) {
      testWidgets(
        '$suite $input inspection disclosure keeps a choice-only result',
        (t) => _semantics(t, () async {
          final (port, module, live) = await _mount(t, suite);
          final before = module.projection.value;
          await _act(t, find.byKey(const Key('preset-preview-open')), input);
          await _tail(t);
          expect(find.byType(StarBridgeExpansionTile), findsNWidgets(2));
          expect(find.byType(ExpansionTile), findsNothing);
          for (var index = 0; index < 2; index++) {
            final tile = find.byType(StarBridgeExpansionTile).at(index);
            final state = t.state(tile);
            final expander = find.descendant(
              of: tile,
              matching: find.byType(SuiteExpander),
            );
            final header = find
                .descendant(of: tile, matching: find.byType(SuitePressable))
                .first;
            expect(t.widget<SuiteExpander>(expander).expanded, isFalse);
            await _act(t, header, input);
            expect(t.widget<SuiteExpander>(expander).expanded, isTrue);
            live.update(() {
              live.suite = suite == InteractionSuite.scan
                  ? InteractionSuite.glow
                  : InteractionSuite.scan;
              live.reduce = true;
              live.light = true;
            });
            await _frames(t);
            expect(t.state(tile), same(state));
            expect(t.widget<SuiteExpander>(expander).expanded, isTrue);
            expect(
              InteractionScope.of(t.element(expander)).reduceMotion,
              isTrue,
            );
            await _act(t, header, input);
            expect(t.widget<SuiteExpander>(expander).expanded, isFalse);
            expect(port.writes, isEmpty);
          }
          await _act(t, _button(_copy(t, 'overlay.workspace.cancel')), input);
          await _tail(t);
          expect(live.decisions, [false]);
          expect(port.writes, isEmpty);
          expect(module.projection.value.snapshot, same(before.snapshot));
          await _act(t, find.byKey(const Key('preset-preview-open')), input);
          await _act(t, find.byKey(const Key('overlay-import-confirm')), input);
          await _tail(t);
          expect(live.decisions, [false, true]);
          expect(live.confirmations, [_source(input)]);
          expect(port.writes, isEmpty);
          expect(module.projection.value.snapshot, same(before.snapshot));
          expect(module.projection.value.settings, same(before.settings));
          await _close(t, module);
        }),
        timeout: _timeout,
      );

      testWidgets(
        '$suite $input preset name keeps native editing and explicit commit',
        (t) => _semantics(t, () async {
          final (port, module, live) = await _mount(t, suite);
          await _act(t, find.byKey(const Key('preset-name-open')), input);
          await _tail(t);
          final field = _name();
          expect(
            find.ancestor(
              of: field,
              matching: find.byType(StarBridgeFieldFrame),
            ),
            findsOneWidget,
          );
          final native = t.widget<TextField>(field);
          final controller = native.controller!;
          final focus = native.focusNode!;
          final editor = t.state(_editor(field));
          expect(native.maxLength, 24);
          expect(native.onSubmitted, isNull);
          await t.enterText(field, '   ');
          await _frames(t);
          final save = find.byKey(const Key('overlay-preset-settings-save'));
          expect(t.widget<StarBridgeActionButton>(save).onActivate, isNull);
          expect(port.writes, isEmpty);
          const composing = TextEditingValue(
            text: 'Draft name',
            selection: TextSelection.collapsed(offset: 5),
            composing: TextRange(start: 0, end: 10),
          );
          t.testTextInput.updateEditingValue(composing);
          await _frames(t);
          live.update(() {
            live.suite = suite == InteractionSuite.rail
                ? InteractionSuite.scan
                : InteractionSuite.rail;
            live.reduce = true;
            live.light = true;
          });
          await _frames(t);
          expect(t.widget<TextField>(field).controller, same(controller));
          expect(t.widget<TextField>(field).focusNode, same(focus));
          expect(t.state(_editor(field)), same(editor));
          expect(controller.value, composing);
          await t.testTextInput.receiveAction(TextInputAction.done);
          await _frames(t);
          expect(port.writes, isEmpty);
          await _act(t, _button(_copy(t, 'overlay.workspace.cancel')), input);
          await _tail(t);
          expect(find.byType(OverlayPresetSettingsDialog), findsNothing);
          expect(port.writes, isEmpty);
          await _act(t, find.byKey(const Key('preset-name-open')), input);
          expect(
            t.widget<TextField>(_name()).controller!.text,
            port.snapshot.presets.first.name,
          );
          await t.enterText(_name(), '  Valid name  ');
          final before = module.projection.value.snapshot;
          port.pending = Completer<OverlayWorkspaceWriteResult>();
          await _act(t, save, input);
          expect(port.writes, hasLength(1));
          expect(
            port.writes.single.kind,
            OverlayWorkspaceMutationKind.configurePresetSources,
          );
          expect(port.writes.single.name, 'Valid name');
          expect(port.writes.single.presetId, 'one');
          expect(port.admissions.single.$2, 1);
          expect(module.projection.value.busy, isTrue);
          expect(module.projection.value.snapshot, same(before));
          expect(t.widget<TextField>(_name()).enabled, isFalse);
          expect(t.widget<StarBridgeActionButton>(save).onActivate, isNull);
          port.revision++;
          port.pending!.complete(
            OverlayWorkspaceWriteResult.completed(port.snapshot),
          );
          await _frames(t, 5);
          await _tail(t);
          expect(find.byType(OverlayPresetSettingsDialog), findsNothing);
          expect(module.projection.value.busy, isFalse);
          expect(port.writes, hasLength(1));
          await _close(t, module);
        }),
        timeout: _timeout,
      );

      testWidgets(
        '$suite $input real page import editor stays native and never saves active',
        (t) => _semantics(t, () async {
          final (port, module, live) = await _mount(t, suite, page: true);
          final saved = module.projection.value.settings!.toMap();
          await _entry(t, 'import', input);
          final field = find.descendant(
            of: find.byType(AlertDialog),
            matching: find.byType(TextField),
          );
          expect(
            find.ancestor(
              of: field,
              matching: find.byType(StarBridgeFieldFrame),
            ),
            findsOneWidget,
          );
          await t.enterText(field, '{invalid-preset');
          final editable = t.widget<EditableText>(_editor(field));
          final controller = editable.controller;
          final focus = editable.focusNode;
          live.update(() {
            live.suite = suite == InteractionSuite.glow
                ? InteractionSuite.scan
                : InteractionSuite.glow;
            live.reduce = true;
          });
          await _frames(t);
          expect(
            t.widget<EditableText>(_editor(field)).controller,
            same(controller),
          );
          expect(t.widget<EditableText>(_editor(field)).focusNode, same(focus));
          expect(controller.text, '{invalid-preset');
          live.update(() => live.reduce = false);
          await _frames(t);
          await _act(
            t,
            _button(_copy(t, 'overlay.importPreview.inspect')),
            input,
          );
          await _frames(t, 2);
          expect(find.byType(OverlayPresetImportPreview), findsNothing);
          expect(port.writes, isEmpty);
          expect(
            find.text(_copy(t, 'overlay.workspace.importInvalid')),
            findsOneWidget,
          );
          if (input != 'pointer') {
            _staticSnack(t);
          }
          await _tail(t);
          final package = OverlayPresetTransfer(
            name: 'Checked import',
            settings: settings(),
            layout: layout,
          ).serialize();
          await _inspect(t, package, input);
          expect(find.byType(OverlayPresetImportPreview), findsOneWidget);
          expect(port.writes, isEmpty);
          await _act(t, _button(_copy(t, 'overlay.workspace.cancel')), input);
          await _tail(t);
          expect(port.writes, isEmpty);
          expect(module.projection.value.settings!.toMap(), saved);
          await _inspect(t, package, input);
          port.pending = Completer<OverlayWorkspaceWriteResult>();
          await _act(t, find.byKey(const Key('overlay-import-confirm')), input);
          await _tail(t);
          expect(port.writes, hasLength(1));
          expect(
            port.writes.single.kind,
            OverlayWorkspaceMutationKind.importPreset,
          );
          expect(port.writes.single.name, 'Checked import');
          expect(port.admissions.single.$3, _source(input));
          expect(module.projection.value.busy, isTrue);
          expect(module.projection.value.settings!.toMap(), saved);
          port.revision++;
          port.pending!.complete(
            OverlayWorkspaceWriteResult.completed(port.snapshot),
          );
          await _frames(t, 5);
          expect(module.projection.value.busy, isFalse);
          expect(module.projection.value.settings!.toMap(), saved);
          expect(
            port.writes.where(
              (w) => w.kind == OverlayWorkspaceMutationKind.saveActive,
            ),
            isEmpty,
          );
          await _close(t, module);
        }),
        timeout: _timeout,
      );
    }

    for (final confirmInput in ['keyboard', 'reader']) {
      testWidgets(
        '$suite pointer inspection final $confirmInput owns actual import',
        (t) => _semantics(t, () async {
          final (port, module, _) = await _mount(t, suite, page: true);
          final originalSettings = module.projection.value.settings!.toMap();
          final package = OverlayPresetTransfer(
            name: 'Mixed final source',
            settings: settings(),
            layout: layout,
          ).serialize();
          await _inspect(t, package, 'pointer');
          expect(find.byType(OverlayPresetImportPreview), findsOneWidget);
          expect(port.writes, isEmpty);
          port.pending = Completer<OverlayWorkspaceWriteResult>();
          await _act(
            t,
            find.byKey(const Key('overlay-import-confirm')),
            confirmInput,
          );
          await _tail(t);
          expect(port.writes, hasLength(1));
          final admission = port.admissions.single;
          expect(admission.$1.kind, OverlayWorkspaceMutationKind.importPreset);
          expect(admission.$1.name, 'Mixed final source');
          expect(admission.$1.settings!.toMap(), settings().toMap());
          expect(
            admission.$1.layout!.map((item) => item.toMap()).toList(),
            layout.map((item) => item.toMap()).toList(),
          );
          expect(admission.$2, 1);
          expect(admission.$3, InteractionSource.keyboard);
          expect(module.projection.value.busy, isTrue);
          expect(module.projection.value.settings!.toMap(), originalSettings);
          port.revision++;
          port.pending!.complete(
            OverlayWorkspaceWriteResult.completed(port.snapshot),
          );
          await _frames(t, 5);
          expect(module.projection.value.busy, isFalse);
          expect(port.writes, hasLength(1));
          expect(
            port.writes.any(
              (mutation) =>
                  mutation.kind == OverlayWorkspaceMutationKind.saveActive,
            ),
            isFalse,
          );
          expect(module.projection.value.settings!.toMap(), originalSettings);
          await _close(t, module);
        }),
        timeout: _timeout,
      );
    }

    testWidgets(
      '$suite actual keyboard export keeps original clipboard payload',
      (t) async {
        String? clipboard;
        t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async {
            if (call.method == 'Clipboard.setData') {
              clipboard = (call.arguments as Map)['text'] as String?;
            }
            return null;
          },
        );
        addTearDown(
          () => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.platform,
            null,
          ),
        );
        final (port, module, _) = await _mount(t, suite, page: true);
        final preset = module.projection.value.snapshot!.presets.first;
        final expected = OverlayPresetTransfer(
          name: preset.name,
          settings: preset.settings,
          layout: preset.layout,
          sources: preset.sources,
        ).serialize();
        await _entry(t, 'export', 'keyboard', finish: false);
        await _frames(t, 2);
        expect(clipboard, expected);
        expect(
          find.text(_copy(t, 'overlay.workspace.exported')),
          findsOneWidget,
        );
        _staticSnack(t);
        expect(port.writes, isEmpty);
        await _close(t, module);
      },
      timeout: _timeout,
    );

    testWidgets(
      '$suite late preset metadata receipt does not recreate dialog',
      (t) async {
        final (port, module, _) = await _mount(t, suite);
        await _act(t, find.byKey(const Key('preset-name-open')), 'keyboard');
        await t.enterText(_name(), 'Late accepted');
        port.pending = Completer<OverlayWorkspaceWriteResult>();
        await _act(
          t,
          find.byKey(const Key('overlay-preset-settings-save')),
          'keyboard',
        );
        expect(port.writes, hasLength(1));
        expect(module.projection.value.busy, isTrue);
        await t.pumpWidget(const SizedBox.shrink());
        await _frames(t);
        port.revision++;
        port.pending!.complete(
          OverlayWorkspaceWriteResult.completed(port.snapshot),
        );
        await _frames(t, 5);
        expect(find.byType(OverlayPresetSettingsDialog), findsNothing);
        expect(port.writes, hasLength(1));
        expect(module.projection.value.busy, isFalse);
        module.dispose();
        expect(t.takeException(), isNull);
      },
      timeout: _timeout,
    );
  }
}
