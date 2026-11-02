import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_action_button.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_activation_origin.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_switch.dart';
import 'package:starbridge_flutter/features/overlay_settings/menu_additional_settings_draft.dart';
import 'package:starbridge_flutter/features/overlay_settings/menu_additional_settings_editors.dart';
import 'package:starbridge_flutter/features/overlay_settings/menu_settings_draft.dart';
import 'package:starbridge_flutter/features/overlay_settings/menu_browser_resume_card.dart';
import 'package:starbridge_flutter/features/overlay_settings/menu_screenshot_directory_card.dart';
import 'package:starbridge_flutter/features/overlay_settings/menu_shortcut_settings_card.dart';
import 'package:starbridge_flutter/features/overlay_settings/menu_overlay_settings.dart';
import 'package:starbridge_flutter/features/overlay_settings/menu_browser_resume_controller.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_local_tools.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_workspace_controller.dart';
import 'package:starbridge_flutter/platform/window/menu_browser_resume.dart';
import 'package:starbridge_flutter/platform/window/menu_screenshot_directory.dart';
import 'package:starbridge_flutter/platform/window/menu_shortcut_settings.dart';

import 'interaction_batch3ca_test.dart' show MenuPort, fire;
import 'interaction_batch3bw_test.dart' show frames;
import 'interaction_batch3i_test.dart' show scopedApp;
import 'interaction_batch3cc_test.dart' show choose;
import '../../features/friends/social_layout_test.dart' show size;

class Operations {
  final calls = <(String, InteractionSource)>[];
  final wait = <String, Completer<void>>{};
  final fail = <String>{};
  Future<void> invoke(String action) async {
    calls.add((action, currentStarBridgeActivationSource));
    await wait[action]?.future;
    if (fail.contains(action)) throw StateError('Synthetic $action refusal');
  }

  void finish() {
    for (final c in wait.values) {
      if (!c.isCompleted) c.complete();
    }
  }
}

class ShortcutPort extends Operations implements MenuShortcutSettingsPort {
  var value = const MenuShortcutSettings(2, 'F9', true, true, 'registered');
  @override
  Future<MenuShortcutSettings> readShortcut() async {
    await invoke('read');
    return value;
  }

  @override
  Future<MenuShortcutSettings> saveShortcut(MenuShortcutSettings next) async {
    await invoke('save');
    return value = MenuShortcutSettings(
      value.revision + 1,
      next.binding,
      next.enabled,
      next.closeWithHotkey,
      next.enabled ? 'registered' : 'disabled',
    );
  }
}

class ResumePort extends Operations implements MenuBrowserResumePort {
  var value = const MenuBrowserResume(2, false, null);
  @override
  Future<MenuBrowserResume> read() async {
    await invoke('read');
    return value;
  }

  @override
  Future<MenuBrowserResume> setEnabled(
    MenuBrowserResume saved,
    bool enabled,
  ) async {
    await invoke('save');
    return value = MenuBrowserResume(
      value.revision + 1,
      enabled,
      enabled ? value.url : null,
    );
  }

  @override
  Future<MenuBrowserResume> remember(MenuBrowserResume saved, String url) =>
      throw StateError('Settings must not remember URLs');
}

class DirectoryPort extends Operations
    implements StagedMenuScreenshotDirectoryPort {
  var value = const MenuScreenshotDirectory(
    revision: 2,
    directory: r'C:\Synthetic\Committed',
    isDefault: false,
  );
  bool cancel = false;
  @override
  Future<MenuScreenshotDirectory> read() async {
    await invoke('read');
    return value;
  }

  @override
  Future<MenuScreenshotDirectorySelection> chooseDraft(
    MenuScreenshotDirectory saved,
  ) async {
    await invoke('draft');
    return MenuScreenshotDirectorySelection(
      revision: saved.revision,
      directory: cancel ? saved.directory : r'C:\Synthetic\Selected',
      token: cancel ? null : 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      cancelled: cancel,
    );
  }

  @override
  Future<MenuScreenshotDirectory> commitDraft(
    MenuScreenshotDirectorySelection selection,
  ) async {
    await invoke('commit');
    return value = MenuScreenshotDirectory(
      revision: value.revision + 1,
      directory: selection.directory,
      isDefault: false,
    );
  }

  @override
  Future<MenuScreenshotDirectory> choose(MenuScreenshotDirectory saved) async {
    await invoke('choose');
    if (cancel) {
      return MenuScreenshotDirectory(
        revision: saved.revision,
        directory: saved.directory,
        isDefault: saved.isDefault,
        cancelled: true,
      );
    }
    return value = MenuScreenshotDirectory(
      revision: value.revision + 1,
      directory: r'C:\Synthetic\Selected',
      isDefault: false,
    );
  }

  @override
  Future<MenuScreenshotDirectory> reset(MenuScreenshotDirectory saved) async {
    await invoke('reset');
    return value = MenuScreenshotDirectory(
      revision: value.revision + 1,
      directory: r'C:\Synthetic\Default',
      isDefault: true,
    );
  }

  @override
  Future<MenuScreenshotDirectory> open(MenuScreenshotDirectory saved) async {
    await invoke('open');
    return MenuScreenshotDirectory(
      revision: saved.revision,
      directory: saved.directory,
      isDefault: saved.isDefault,
      opened: true,
    );
  }
}

class Fixture {
  final shortcut = ShortcutPort(),
      resume = ResumePort(),
      directory = DirectoryPort(),
      window = MenuPort();
  late final extra = MenuAdditionalSettingsDraft(
    shortcutPort: shortcut,
    resumePort: resume,
    directoryPort: directory,
  );
  late final draft = MenuSettingsDraft(window)..attachAdditional(extra);
  bool disposed = false;
  Future<void> ready() async {
    await draft.initialize();
    await extra.reload();
  }

  Operations port(String kind) => switch (kind.replaceFirst('staged-', '')) {
    'shortcut' => shortcut,
    'resume' => resume,
    _ => directory,
  };
  void finish() {
    shortcut.finish();
    resume.finish();
    directory.finish();
  }

  void dispose() {
    if (!disposed) {
      disposed = true;
      draft.dispose();
    }
  }

  Future<void> clean(WidgetTester t) async {
    finish();
    await frames(t);
    await t.pumpWidget(const SizedBox());
    await t.pump();
    dispose();
  }
}

class Harness extends StatefulWidget {
  const Harness(this.f, this.suite, this.kind, {super.key});
  final Fixture f;
  final InteractionSuite suite;
  final String kind;
  @override
  State<Harness> createState() => HarnessState();
}

class HarnessState extends State<Harness> {
  late Fixture current = widget.f;
  bool reduce = false, light = false, visible = true;
  void change(VoidCallback action) => setState(action);
  @override
  Widget build(BuildContext context) => scopedApp(
    visible
        ? SingleChildScrollView(
            child: switch (widget.kind) {
              'staged-directory' => MenuAdditionalDirectoryEditor(
                draft: current.extra,
              ),
              'staged-resume' => MenuAdditionalResumeEditor(
                draft: current.extra,
              ),
              'staged-shortcut' => MenuAdditionalShortcutEditor(
                draft: current.extra,
              ),
              'directory' => MenuScreenshotDirectoryCard(
                port: current.directory,
              ),
              'resume' => MenuBrowserResumeCard(port: current.resume),
              _ => MenuShortcutSettingsCard(port: current.shortcut),
            },
          )
        : const SizedBox(),
    widget.suite,
    reduce: reduce,
    light: light,
  );
}

Future<HarnessState> mount(
  WidgetTester t,
  Fixture f,
  InteractionSuite suite,
  String kind,
) async {
  final k = GlobalKey<HarnessState>();
  await t.pumpWidget(Harness(f, suite, kind, key: k));
  await frames(t);
  return k.currentState!;
}

Future<void> activate(WidgetTester t, String input, String id) async {
  final target = find.byKey(Key(id));
  final toggle = find.ancestor(
    of: target,
    matching: find.byType(StarBridgeSwitch),
  );
  await fire(
    t,
    input,
    input == 'pointer' && toggle.evaluate().isNotEmpty ? toggle.first : target,
  );
}

InteractionSource origin(String input) =>
    input == 'pointer' ? InteractionSource.pointer : InteractionSource.keyboard;
void busy(WidgetTester t, String input) {
  expect(find.byType(SuiteBusyLabel), findsOneWidget);
  final context = t.element(find.byType(SuiteBusyLabel));
  expect(InteractionScope.of(context).reduceMotion, input != 'pointer');
}

List<(String, InteractionSource)> calls(Operations p, String action) =>
    p.calls.where((c) => c.$1 == action).toList();

void main() {
  for (final suite in InteractionSuite.values) {
    for (final input in ['pointer', 'keyboard', 'reader']) {
      for (final reject in [false, true]) {
        testWidgets(
          '$suite $input real main workspace directory save reject=$reject',
          (t) async {
            final semantics = t.ensureSemantics();
            final f = Fixture();
            try {
              size(t, const Size(1100, 1000));
              await f.ready();
              await t.pumpWidget(
                scopedApp(
                  MenuOverlaySettings(preview: null, draft: f.draft),
                  suite,
                ),
              );
              await frames(t);
              await choose(t, input, 'screenshot');
              await activate(t, input, 'menu-screenshot-directory-choose');
              await frames(t);
              expect(f.draft.dirty, true);
              expect(calls(f.directory, 'commit'), isEmpty);
              expect(f.directory.value.directory, r'C:\Synthetic\Committed');
              f.directory.wait['commit'] = Completer();
              if (reject) f.directory.fail.add('commit');
              await activate(t, input, 'menu-workspace-save');
              await frames(t);
              expect(f.draft.busy, true);
              expect(calls(f.directory, 'commit').single.$2, origin(input));
              expect(f.directory.value.directory, r'C:\Synthetic\Committed');
              f.directory.wait['commit']!.complete();
              await frames(t);
              expect(f.draft.dirty, reject);
              expect(f.draft.failed, reject);
              if (reject) {
                expect(find.text(r'C:\Synthetic\Selected'), findsOneWidget);
                f.directory.fail.clear();
                await activate(t, input, 'menu-workspace-save');
                await frames(t);
                expect(f.draft.dirty, false);
                expect(calls(f.directory, 'commit'), hasLength(2));
              }
              expect(f.directory.value.directory, r'C:\Synthetic\Selected');
              expect(calls(f.directory, 'choose'), isEmpty);
            } finally {
              semantics.dispose();
              await f.clean(t);
            }
          },
        );
      }
      testWidgets(
        '$suite $input actual auxiliary MenuLocalSettings retains immediate owners',
        (t) async {
          final semantics = t.ensureSemantics();
          final f = Fixture();
          final tools = MenuLocalToolsController((_, _) async => null);
          final workspace = MenuWorkspaceController(
            scope: Object(),
            panels: const [],
          );
          final resume = MenuBrowserResumeController(f.resume);
          try {
            size(t, const Size(1100, 1000));
            await t.pumpWidget(
              scopedApp(
                MenuLocalSettings(
                  tools: tools,
                  workspace: workspace,
                  shortcutSettings: f.shortcut,
                  browserResume: resume,
                  screenshotDirectory: f.directory,
                ),
                suite,
              ),
            );
            await frames(t);
            await activate(t, input, 'menu-shortcut-close');
            await frames(t);
            expect(calls(f.shortcut, 'save'), isEmpty);
            await activate(t, input, 'menu-shortcut-save');
            await frames(t);
            expect(f.shortcut.value.closeWithHotkey, false);
            await activate(t, input, 'menu-browser-resume-toggle');
            await frames(t);
            expect(f.resume.value.enabled, true);
            await activate(t, input, 'menu-screenshot-directory-choose');
            await frames(t);
            expect(f.directory.value.directory, r'C:\Synthetic\Selected');
            for (final p in [f.shortcut, f.resume]) {
              expect(calls(p, 'save').single.$2, origin(input));
            }
            expect(calls(f.directory, 'choose').single.$2, origin(input));
            expect(calls(f.directory, 'draft'), isEmpty);
            expect(calls(f.directory, 'commit'), isEmpty);
            expect(f.window.sources, isEmpty);
          } finally {
            semantics.dispose();
            await f.clean(t);
            resume.dispose();
            tools.dispose();
            workspace.dispose();
          }
        },
      );
      for (final kind in ['shortcut', 'resume']) {
        testWidgets('$suite $input staged $kind keeps page save authority', (
          t,
        ) async {
          final semantics = t.ensureSemantics();
          final f = Fixture();
          try {
            await f.ready();
            await mount(t, f, suite, 'staged-$kind');
            await activate(
              t,
              input,
              kind == 'shortcut'
                  ? 'menu-shortcut-close'
                  : 'menu-browser-resume-toggle',
            );
            await frames(t);
            expect(f.extra.dirty, true);
            expect(f.draft.dirty, true);
            expect(
              kind == 'shortcut'
                  ? f.extra.shortcut!.closeWithHotkey
                  : f.extra.resume!.enabled,
              kind != 'shortcut',
            );
            expect(calls(f.port(kind), 'save'), isEmpty);
            expect(f.window.sources, isEmpty);
            expect(find.byKey(const Key('menu-shortcut-save')), findsNothing);
            f.draft.discard();
            await frames(t);
            expect(f.extra.dirty, false);
          } finally {
            semantics.dispose();
            await f.clean(t);
          }
        });
      }
      for (final result in ['success', 'cancel', 'failure']) {
        testWidgets(
          '$suite $input staged directory $result never commits before save',
          (t) async {
            final semantics = t.ensureSemantics();
            final f = Fixture();
            try {
              await f.ready();
              final before = f.directory.value;
              f.directory.wait['draft'] = Completer();
              f.directory.cancel = result == 'cancel';
              if (result == 'failure') f.directory.fail.add('draft');
              await mount(t, f, suite, 'staged-directory');
              await activate(t, input, 'menu-screenshot-directory-choose');
              await t.pump();
              busy(t, input);
              expect(calls(f.directory, 'draft').single.$2, origin(input));
              expect(f.directory.value, same(before));
              expect(f.extra.dirty, false);
              expect(calls(f.directory, 'choose'), isEmpty);
              expect(calls(f.directory, 'commit'), isEmpty);
              f.directory.wait['draft']!.complete();
              await frames(t);
              expect(f.extra.dirty, result == 'success');
              expect(f.extra.failed, result == 'failure');
              expect(f.directory.value, same(before));
              if (result == 'success') {
                expect(find.text(r'C:\Synthetic\Selected'), findsOneWidget);
                await activate(t, input, 'menu-screenshot-directory-reset');
                await frames(t);
                expect(f.extra.resetPending, true);
                expect(calls(f.directory, 'reset'), isEmpty);
                f.draft.discard();
                await frames(t);
                expect(f.extra.dirty, false);
              }
            } finally {
              semantics.dispose();
              await f.clean(t);
            }
          },
        );
      }
      for (final action in ['choose', 'reset', 'open']) {
        for (final result in [
          'success',
          'failure',
          if (action == 'choose') 'cancel',
        ]) {
          testWidgets(
            '$suite $input immediate directory $action $result waits receipt',
            (t) async {
              final semantics = t.ensureSemantics();
              final f = Fixture();
              try {
                await mount(t, f, suite, 'directory');
                final before = f.directory.value;
                f.directory.wait[action] = Completer();
                f.directory.cancel = result == 'cancel';
                if (result == 'failure') f.directory.fail.add(action);
                await activate(t, input, 'menu-screenshot-directory-$action');
                await t.pump();
                busy(t, input);
                expect(calls(f.directory, action).single.$2, origin(input));
                expect(f.directory.value, same(before));
                final button = find.ancestor(
                  of: find.byKey(Key('menu-screenshot-directory-$action')),
                  matching: find.byType(StarBridgeActionButton),
                );
                expect(
                  t.widget<StarBridgeActionButton>(button).onActivate,
                  isNull,
                );
                f.directory.wait[action]!.complete();
                await frames(t);
                expect(find.byType(SuiteBusyLabel), findsNothing);
                if (result == 'failure') {
                  expect(f.directory.value, same(before));
                  final disabled = t.widget<StarBridgeActionButton>(
                    find.ancestor(
                      of: find.byKey(
                        const Key('menu-screenshot-directory-open'),
                      ),
                      matching: find.byType(StarBridgeActionButton),
                    ),
                  );
                  expect(disabled.onActivate, isNull);
                  f.directory.fail.clear();
                  await activate(t, input, 'menu-screenshot-directory-reload');
                  await frames(t);
                  expect(calls(f.directory, 'read').last.$2, origin(input));
                } else if (result == 'cancel' || action == 'open') {
                  expect(f.directory.value, same(before));
                } else {
                  expect(f.directory.value.revision, before.revision + 1);
                }
              } finally {
                semantics.dispose();
                await f.clean(t);
              }
            },
          );
        }
      }
      for (final result in ['success', 'failure']) {
        testWidgets(
          '$suite $input immediate resume $result no optimistic consent',
          (t) async {
            final semantics = t.ensureSemantics();
            final f = Fixture();
            try {
              await mount(t, f, suite, 'resume');
              f.resume.wait['save'] = Completer();
              if (result == 'failure') f.resume.fail.add('save');
              await activate(t, input, 'menu-browser-resume-toggle');
              await t.pump();
              busy(t, input);
              expect(f.resume.value.enabled, false);
              expect(calls(f.resume, 'save').single.$2, origin(input));
              f.resume.wait['save']!.complete();
              await frames(t);
              expect(f.resume.value.enabled, result == 'success');
              expect(find.textContaining('https://'), findsNothing);
              if (result == 'failure') {
                expect(
                  find.byKey(const Key('menu-browser-resume-toggle')),
                  findsNothing,
                );
                f.resume.fail.clear();
                await activate(t, input, 'menu-browser-resume-reload');
                await frames(t);
                expect(
                  find.byKey(const Key('menu-browser-resume-toggle')),
                  findsOneWidget,
                );
              }
            } finally {
              semantics.dispose();
              await f.clean(t);
            }
          },
        );
        testWidgets(
          '$suite $input immediate shortcut $result preserves draft on reject',
          (t) async {
            final semantics = t.ensureSemantics();
            final f = Fixture();
            try {
              await mount(t, f, suite, 'shortcut');
              await activate(t, input, 'menu-shortcut-close');
              await frames(t);
              expect(calls(f.shortcut, 'save'), isEmpty);
              expect(f.shortcut.value.closeWithHotkey, true);
              f.shortcut.wait['save'] = Completer();
              if (result == 'failure') f.shortcut.fail.add('save');
              await activate(t, input, 'menu-shortcut-save');
              await t.pump();
              busy(t, input);
              expect(calls(f.shortcut, 'save').single.$2, origin(input));
              expect(f.shortcut.value.closeWithHotkey, true);
              f.shortcut.wait['save']!.complete();
              await frames(t);
              expect(f.shortcut.value.closeWithHotkey, result != 'success');
              if (result == 'failure') {
                expect(
                  find.byKey(const Key('menu-shortcut-error')),
                  findsOneWidget,
                );
                f.shortcut.fail.clear();
                await activate(t, input, 'menu-shortcut-reload');
                await frames(t);
                await activate(t, input, 'menu-shortcut-save');
                await frames(t);
                expect(f.shortcut.value.closeWithHotkey, false);
                expect(calls(f.shortcut, 'save'), hasLength(2));
              }
            } finally {
              semantics.dispose();
              await f.clean(t);
            }
          },
        );
      }
      for (final kind in [
        'directory',
        'resume',
        'shortcut',
        'staged-directory',
        'staged-resume',
        'staged-shortcut',
      ]) {
        testWidgets(
          '$suite $input $kind read failure explicit reload waits actual read',
          (t) async {
            final semantics = t.ensureSemantics();
            final f = Fixture();
            try {
              f.port(kind).fail.add('read');
              if (kind.startsWith('staged-')) await f.ready();
              await mount(t, f, suite, kind);
              f.port(kind).fail.clear();
              f.port(kind).wait['read'] = Completer();
              final id = kind.startsWith('staged-')
                  ? 'menu-additional-${kind.replaceFirst('staged-', '')}-reload'
                  : kind == 'directory'
                  ? 'menu-screenshot-directory-reload'
                  : kind == 'resume'
                  ? 'menu-browser-resume-reload'
                  : 'menu-shortcut-reload';
              await activate(t, input, id);
              await t.pump();
              busy(t, input);
              expect(calls(f.port(kind), 'read').last.$2, origin(input));
              f.port(kind).wait['read']!.complete();
              await frames(t);
              expect(find.byType(SuiteBusyLabel), findsNothing);
            } finally {
              semantics.dispose();
              await f.clean(t);
            }
          },
        );
      }
    }
    for (final kind in [
      'directory',
      'resume',
      'shortcut',
      'staged-directory',
    ]) {
      testWidgets(
        '$suite $kind live reduced motion and palette affect actual pointer wait',
        (t) async {
          final f = Fixture();
          try {
            if (kind.startsWith('staged-')) await f.ready();
            final h = await mount(t, f, suite, kind);
            if (kind == 'shortcut') {
              await activate(t, 'pointer', 'menu-shortcut-close');
              await frames(t);
            }
            final action = kind == 'directory'
                ? 'choose'
                : kind == 'resume'
                ? 'save'
                : kind == 'shortcut'
                ? 'save'
                : 'draft';
            f.port(kind).wait[action] = Completer();
            await activate(
              t,
              'pointer',
              kind == 'resume'
                  ? 'menu-browser-resume-toggle'
                  : kind == 'shortcut'
                  ? 'menu-shortcut-save'
                  : 'menu-screenshot-directory-choose',
            );
            await t.pump();
            busy(t, 'pointer');
            h.change(() {
              h.reduce = true;
              h.light = true;
            });
            await t.pump();
            await t.pump();
            busy(t, 'keyboard');
            expect(
              Theme.of(t.element(find.byType(SuiteBusyLabel))).brightness,
              Brightness.light,
            );
            h.change(() => h.reduce = false);
            await t.pump();
            await t.pump();
            busy(t, 'pointer');
          } finally {
            await f.clean(t);
          }
        },
      );
      testWidgets(
        '$suite $kind late old completion cannot clear new owner wait',
        (t) async {
          final f = Fixture(), second = Fixture();
          try {
            if (kind.startsWith('staged-')) {
              await f.ready();
              await second.ready();
            }
            final h = await mount(t, f, suite, kind);
            final action = kind == 'directory'
                ? 'choose'
                : kind == 'resume'
                ? 'save'
                : kind == 'shortcut'
                ? 'save'
                : 'draft';
            final id = kind == 'resume'
                ? 'menu-browser-resume-toggle'
                : kind == 'shortcut'
                ? 'menu-shortcut-save'
                : 'menu-screenshot-directory-choose';
            if (kind == 'shortcut') {
              await activate(t, 'pointer', 'menu-shortcut-close');
              await frames(t);
            }
            f.port(kind).wait[action] = Completer();
            await activate(t, 'pointer', id);
            await frames(t);
            h.change(() => h.current = second);
            await frames(t);
            if (kind == 'shortcut') {
              await activate(t, 'pointer', 'menu-shortcut-close');
              await frames(t);
            }
            second.port(kind).wait[action] = Completer();
            await activate(t, 'pointer', id);
            await frames(t);
            f.port(kind).wait[action]!.complete();
            await frames(t);
            busy(t, 'pointer');
            expect(calls(second.port(kind), action), hasLength(1));
            expect(
              calls(second.port(kind), action).single.$2,
              InteractionSource.pointer,
            );
            h.change(() => h.reduce = true);
            await t.pump();
            await t.pump();
            busy(t, 'keyboard');
            second.port(kind).wait[action]!.complete();
            await frames(t);
            expect(find.byType(SuiteBusyLabel), findsNothing);
            expect(t.takeException(), isNull);
          } finally {
            second.finish();
            await f.clean(t);
            second.dispose();
          }
        },
      );
      testWidgets(
        '$suite $kind remove pending editor never mutates disposed UI',
        (t) async {
          final f = Fixture();
          try {
            if (kind.startsWith('staged-')) await f.ready();
            final h = await mount(t, f, suite, kind);
            if (kind == 'shortcut') {
              await activate(t, 'pointer', 'menu-shortcut-close');
              await frames(t);
            }
            final action = kind == 'directory'
                ? 'choose'
                : kind == 'resume'
                ? 'save'
                : kind == 'shortcut'
                ? 'save'
                : 'draft';
            f.port(kind).wait[action] = Completer();
            await activate(
              t,
              'pointer',
              kind == 'resume'
                  ? 'menu-browser-resume-toggle'
                  : kind == 'shortcut'
                  ? 'menu-shortcut-save'
                  : 'menu-screenshot-directory-choose',
            );
            await frames(t);
            h.change(() => h.visible = false);
            await t.pump();
            f.port(kind).wait[action]!.complete();
            await frames(t);
            expect(t.takeException(), isNull);
          } finally {
            await f.clean(t);
          }
        },
      );
    }
  }
}
