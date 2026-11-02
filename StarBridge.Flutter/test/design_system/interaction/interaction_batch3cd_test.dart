import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_activation_origin.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_action_row.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_select_form_field.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_workspace_module.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_workspace_page.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_workspace_preview_stage.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_workspace_layout_editor.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_workspace_editor_state.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_workspace_models.dart';

import 'interaction_batch3bz_test.dart' show WorkspacePort;
import 'interaction_batch3ca_test.dart'
    show key, fire, MenuFixture, MenuHarness;
import 'interaction_batch3i_test.dart' show scopedApp;
import 'interaction_batch3bw_test.dart' show frames;

class ReadPort extends WorkspacePort {
  int reads = 0;
  bool failRead = false;
  Completer<void>? readPending;
  final readSources = <InteractionSource>[];
  @override
  Future<OverlayWorkspaceSnapshot> read() async {
    reads++;
    readSources.add(currentStarBridgeActivationSource);
    await readPending?.future;
    if (failRead) throw StateError('Synthetic unavailable');
    return snapshot;
  }
}

class Fixture {
  final port = ReadPort();
  late final module = OverlayWorkspaceModule(port);
  final editor = OverlayWorkspaceEditorState();
  Future<void> ready() => module.initialize();
  Future<void> dirtyFailure() async {
    module.updateSetting('showMembers', true);
    port.reject = true;
    expect(await module.save(), isFalse);
  }

  Future<void> clean(WidgetTester t) async {
    if (port.readPending case final p? when !p.isCompleted) p.complete();
    await frames(t);
    await t.pumpWidget(const SizedBox());
    await t.pump();
    module.dispose();
    editor.dispose();
  }
}

class Harness extends StatefulWidget {
  const Harness(this.fixture, this.suite, {this.stage = false, super.key});
  final Fixture fixture;
  final InteractionSuite suite;
  final bool stage;
  @override
  State<Harness> createState() => HarnessState();
}

class HarnessState extends State<Harness> {
  late var h = widget.fixture;
  late var suite = widget.suite;
  bool reduce = false, light = false, visible = true;
  void change(VoidCallback action) => setState(action);
  @override
  Widget build(BuildContext context) => scopedApp(
    !visible
        ? const SizedBox()
        : widget.stage
        ? ValueListenableBuilder(
            valueListenable: h.module.projection,
            builder: (_, p, _) => OverlayWorkspacePreviewStage(
              projection: p,
              module: h.module,
              editor: h.editor,
            ),
          )
        : OverlayWorkspacePage(module: h.module),
    suite,
    reduce: reduce,
    light: light,
  );
}

void viewport(WidgetTester t, double width) {
  t.view.physicalSize = Size(width, 1000);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
}

Future<HarnessState> mount(
  WidgetTester t,
  Fixture h,
  InteractionSuite suite, {
  bool stage = false,
  double width = 1400,
}) async {
  viewport(t, width);
  final k = GlobalKey<HarnessState>();
  await t.pumpWidget(Harness(h, suite, stage: stage, key: k));
  await frames(t);
  return k.currentState!;
}

Finder get menus => find.byWidgetPredicate(
  (w) => w is SuiteSurfaceTransition && w.kind == SurfaceKind.menu,
);
Future<void> background(WidgetTester t, String input, String value) async {
  await key(t, input, 'overlay-preview-background');
  await frames(t);
  expect(menus, findsOneWidget);
  await fire(
    t,
    input,
    find.byKey(ValueKey<Object>('overlay-preview-background-$value')),
  );
}

class Picker {
  static const channel = MethodChannel('starbridge/gameplay_files');
  int calls = 0;
  Completer<String?>? pending;
  String? path;
  bool fail = false;
  void install() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'pickOverlayBackground');
          calls++;
          final value = pending == null ? path : await pending!.future;
          if (fail) throw PlatformException(code: 'synthetic-picker-failure');
          return value;
        });
  }

  Future<void> clean(WidgetTester t) async {
    if (pending case final p? when !p.isCompleted) p.complete(null);
    await frames(t);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  }
}

Future<void> settlePicker(WidgetTester t) async {
  // Each file/codec await can resume in the test's fake zone. Alternate actual
  // I/O turns and frames; a single real delay followed by virtual frames is
  // not evidence that the read/validation chain completed.
  for (
    var i = 0;
    i < 100 && find.byType(SuiteBusyLabel).evaluate().isNotEmpty;
    i++
  ) {
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await t.pump();
  }
  await frames(t);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;
  late File imageFile;
  setUpAll(() async {
    temp = await Directory.systemTemp.createTemp('starbridge-motion-preview-');
    imageFile = File('${temp.path}/synthetic.png');
    await imageFile.writeAsBytes(
      base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aXioAAAAASUVORK5CYII=',
      ),
    );
  });
  tearDownAll(() async {
    if (await imageFile.exists()) await imageFile.delete();
    await temp.delete();
  });
  for (final suite in InteractionSuite.values) {
    testWidgets('$suite initial information read respects keyboard viewport', (
      t,
    ) async {
      final h = Fixture();
      try {
        viewport(t, 1400);
        h.port.readPending = Completer<void>();
        unawaited(h.module.initialize());
        await t.pumpWidget(
          scopedApp(
            Builder(
              builder: (context) => starBridgeInitialReadViewport(
                context,
                source: InteractionSource.keyboard,
                child: OverlayWorkspacePage(module: h.module),
              ),
            ),
            suite,
          ),
        );
        await t.pump();
        await t.pump();
        expect(h.port.reads, 1);
        expect(
          InteractionScope.of(t.element(find.byType(SuiteBusyFrame)))
              .reduceMotion,
          isTrue,
        );
        h.port.readPending!.complete();
        await frames(t);
        expect(h.module.projection.value.available, isTrue);
        expect(h.port.writes, isEmpty);
      } finally {
        await h.clean(t);
      }
    });
    testWidgets(
      '$suite background popup retires before information group changes',
      (t) async {
        final h = Fixture();
        try {
          await h.ready();
          await mount(t, h, suite, width: 1100);
          await key(t, 'pointer', 'overlay-preview-background');
          await frames(t);
          expect(menus, findsOneWidget);
          await key(t, 'pointer', 'overlay-workspace-group-command');
          await frames(t);
          expect(menus, findsOneWidget);
          await fire(
            t,
            'pointer',
            find.byKey(
              const ValueKey<Object>(('overlay-workspace-group', 'chat')),
            ),
          );
          await frames(t);
          expect(menus, findsNothing);
          expect(
            find.byKey(const ValueKey('overlay-group-compact-chat')),
            findsOneWidget,
          );
          expect(h.module.projection.value.dirty, isFalse);
          expect(h.port.writes, isEmpty);
          expect(t.takeException(), isNull);
        } finally {
          await h.clean(t);
        }
      },
    );
    testWidgets('$suite old picker reply cannot end new owner picker', (
      t,
    ) async {
      final first = Fixture(), second = Fixture();
      final picker = Picker();
      picker.install();
      final semantics = t.ensureSemantics();
      final a = Completer<String?>(), b = Completer<String?>();
      try {
        await first.ready();
        await second.ready();
        final state = await mount(t, first, suite, stage: true);
        picker.pending = a;
        await background(t, 'pointer', 'image');
        state.change(() => state.h = second);
        await frames(t);
        picker.pending = b;
        await background(t, 'reader', 'image');
        expect(picker.calls, 2);
        a.complete(null);
        await frames(t);
        expect(find.byType(SuiteBusyLabel), findsOneWidget);
        expect(
          InteractionScope.of(t.element(find.byType(SuiteBusyFrame)))
              .reduceMotion,
          isTrue,
        );
        expect(find.byType(Image), findsNothing);
        b.complete(null);
        await frames(t);
        expect(find.byType(SuiteBusyLabel), findsNothing);
        expect(first.port.writes, isEmpty);
        expect(second.port.writes, isEmpty);
        expect(t.takeException(), isNull);
      } finally {
        if (!a.isCompleted) a.complete(null);
        if (!b.isCompleted) b.complete(null);
        semantics.dispose();
        await picker.clean(t);
        await first.clean(t);
        await second.clean(t);
      }
    });
    for (final input in ['pointer', 'keyboard', 'reader']) {
      for (final reject in [false, true]) {
        testWidgets(
          '$suite $input unavailable retry reject=$reject reads only',
          (t) async {
            final h = Fixture();
            final semantics = t.ensureSemantics();
            try {
              h.port.failRead = true;
              await h.ready();
              await mount(t, h, suite);
              expect(h.module.projection.value.available, isFalse);
              h.port.failRead = reject;
              h.port.readPending = Completer<void>();
              await key(t, input, 'overlay-workspace-reload');
              expect(find.byType(AlertDialog), findsNothing);
              expect(h.port.reads, 2);
              expect(
                h.port.readSources.last,
                input == 'pointer'
                    ? InteractionSource.pointer
                    : InteractionSource.keyboard,
              );
              expect(
                InteractionScope.of(t.element(find.byType(SuiteBusyFrame)))
                    .reduceMotion,
                input != 'pointer',
              );
              h.port.readPending!.complete();
              await frames(t);
              expect(h.module.projection.value.available, !reject);
              expect(find.byType(SuiteBusyLabel), findsNothing);
              expect(h.port.writes, isEmpty);
            } finally {
              semantics.dispose();
              await h.clean(t);
            }
          },
        );
      }
      testWidgets(
        '$suite $input information group and both fit modes retain owners',
        (t) async {
          final h = Fixture();
          final semantics = t.ensureSemantics();
          try {
            await h.ready();
            await mount(t, h, suite, width: 1100);
            h.module.updateSetting('showMembers', true);
            await frames(t);
            await key(t, input, 'overlay-workspace-group-command');
            await frames(t);
            await fire(
              t,
              input,
              find.byKey(
                const ValueKey<Object>(('overlay-workspace-group', 'members')),
              ),
            );
            await frames(t);
            final field = find.byKey(
              const ValueKey('overlay-group-compact-members'),
            );
            expect(
              t.widget<StarBridgeSelectFormField<String>>(field).initialValue,
              'members',
            );
            expect(t.state<FormFieldState<String>>(field).value, 'members');
            await key(t, input, 'overlay-settings-expand');
            await frames(t);
            final before = h.module.projection.value.layout;
            await key(t, input, 'overlay-preview-zoom');
            await frames(t);
            final viewer = t.widget<InteractiveViewer>(
              find.byKey(const Key('overlay-preview-actual-size')),
            );
            expect(viewer.scaleEnabled, isFalse);
            expect(
              viewer.transformationController!.value.getMaxScaleOnAxis(),
              1,
            );
            await key(t, input, 'overlay-preview-zoom');
            await frames(t);
            expect(
              find.byKey(const Key('overlay-preview-actual-size')),
              findsNothing,
            );
            expect(h.module.projection.value.layout, before);
            // The edit saved once; fitting the preview writes nothing more.
            expect(h.module.projection.value.dirty, isFalse);
            expect(h.port.writes, hasLength(1));
            expect(h.port.reads, 1);
            expect(t.takeException(), isNull);
          } finally {
            semantics.dispose();
            await h.clean(t);
          }
        },
      );
      testWidgets(
        '$suite $input failed-save retry saves again without reading',
        (t) async {
          final h = Fixture();
          final semantics = t.ensureSemantics();
          try {
            await h.ready();
            await h.dirtyFailure();
            await mount(t, h, suite);
            final writes = h.port.writes.length, reads = h.port.reads;
            h.port.reject = false;
            await key(t, input, 'overlay-workspace-retry-failure');
            await frames(t);
            expect(find.byType(AlertDialog), findsNothing);
            expect(h.port.reads, reads);
            expect(h.port.writes, hasLength(writes + 1));
            expect(h.module.projection.value.dirty, isFalse);
            expect(h.module.projection.value.failure, isNull);
            expect(h.module.projection.value.settings!['showMembers'], isTrue);
            expect(
              find.byKey(const Key('overlay-workspace-retry-failure')),
              findsNothing,
            );
            expect(t.takeException(), isNull);
          } finally {
            semantics.dispose();
            await h.clean(t);
          }
        },
      );
      testWidgets(
        '$suite $input failed-save discard returns to the saved settings',
        (t) async {
          final h = Fixture();
          final semantics = t.ensureSemantics();
          try {
            await h.ready();
            await h.dirtyFailure();
            await mount(t, h, suite);
            final writes = h.port.writes.length, reads = h.port.reads;
            await key(t, input, 'overlay-workspace-discard-failed');
            await frames(t);
            expect(find.byType(AlertDialog), findsNothing);
            expect(h.port.reads, reads);
            expect(h.port.writes, hasLength(writes));
            expect(h.module.projection.value.dirty, isFalse);
            expect(h.module.projection.value.failure, isNull);
            expect(h.module.projection.value.settings!['showMembers'], isFalse);
            expect(t.takeException(), isNull);
          } finally {
            semantics.dispose();
            await h.clean(t);
          }
        },
      );
      for (final outcome in ['cancel', 'failure', 'image']) {
        testWidgets(
          '$suite $input local image outcome=$outcome preserves preview and no writes',
          (t) async {
            final h = Fixture();
            final picker = Picker()..pending = Completer<String?>();
            picker.install();
            final semantics = t.ensureSemantics();
            try {
              await h.ready();
              final state = await mount(t, h, suite, stage: true);
              await background(t, input, 'space');
              await frames(t);
              expect(
                t
                    .widget<OverlayWorkspaceInteractivePreview>(
                      find.byType(OverlayWorkspaceInteractivePreview),
                    )
                    .showGrid,
                isFalse,
              );
              await background(t, input, 'image');
              expect(picker.calls, 1);
              expect(find.byType(SuiteBusyLabel), findsOneWidget);
              expect(
                InteractionScope.of(t.element(find.byType(SuiteBusyFrame)))
                    .reduceMotion,
                input != 'pointer',
              );
              final target = find.ancestor(
                of: find.byKey(const Key('overlay-preview-background')),
                matching: find.byType(StarBridgeActionRow),
              );
              expect(t.widget<StarBridgeActionRow>(target).onActivate, isNull);
              state.change(() => state.reduce = true);
              await t.pump();
              await t.pump();
              expect(
                InteractionScope.of(t.element(find.byType(SuiteBusyFrame)))
                    .reduceMotion,
                isTrue,
              );
              picker.fail = outcome == 'failure';
              picker.pending!.complete(
                outcome == 'image' ? imageFile.path : null,
              );
              await settlePicker(t);
              expect(find.byType(SuiteBusyLabel), findsNothing);
              expect(
                t
                    .widget<OverlayWorkspaceInteractivePreview>(
                      find.byType(OverlayWorkspaceInteractivePreview),
                    )
                    .showGrid,
                isFalse,
              );
              expect(
                find.byType(Image),
                outcome == 'image' ? findsOneWidget : findsNothing,
              );
              expect(
                find.byType(SnackBar),
                outcome == 'failure' ? findsOneWidget : findsNothing,
              );
              expect(h.module.projection.value.dirty, isFalse);
              expect(h.port.writes, isEmpty);
              expect(picker.calls, 1);
              expect(t.takeException(), isNull);
            } finally {
              semantics.dispose();
              await picker.clean(t);
              await h.clean(t);
            }
          },
        );
      }
    }
    testWidgets(
      '$suite menu synthetic preview fit never saves or invokes tools',
      (t) async {
        final h = MenuFixture();
        try {
          viewport(t, 1400);
          await h.load();
          await t.pumpWidget(MenuHarness(h, suite));
          await frames(t);
          for (final input in ['pointer', 'keyboard', 'pointer', 'keyboard']) {
            await key(t, input, 'menu-preview-zoom');
            await frames(t);
          }
          expect(h.port.sources, isEmpty);
          expect(h.resume.sources, isEmpty);
          expect(h.draft.dirty, isTrue);
          expect(t.takeException(), isNull);
        } finally {
          await h.clean(t);
        }
      },
    );
    testWidgets(
      '$suite image request after stage leaves cannot show error or mutate',
      (t) async {
        final h = Fixture();
        final picker = Picker()..pending = Completer<String?>();
        picker.install();
        try {
          await h.ready();
          final state = await mount(t, h, suite, stage: true);
          await background(t, 'pointer', 'image');
          state.change(() => state.visible = false);
          await t.pump();
          picker.fail = true;
          picker.pending!.complete(null);
          await frames(t);
          expect(find.byType(SnackBar), findsNothing);
          expect(h.port.writes, isEmpty);
          expect(t.takeException(), isNull);
        } finally {
          await picker.clean(t);
          await h.clean(t);
        }
      },
    );
  }
}
