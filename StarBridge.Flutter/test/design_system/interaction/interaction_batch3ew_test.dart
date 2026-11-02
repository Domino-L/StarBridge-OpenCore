import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_action_button.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_activation_origin.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_select_form_field.dart';
import 'package:starbridge_flutter/features/party_rooms/example_party_rooms_adapter.dart';
import 'package:starbridge_flutter/features/party_rooms/party_rooms_module.dart';
import 'package:starbridge_flutter/features/party_rooms/party_rooms_page.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../features/friends/social_layout_test.dart' show loadFonts, size;
import '../../features/party_rooms/party_rooms_test.dart'
    show TestRoomsPort, ready, wire;
import 'interaction_batch3aa_test.dart' show select;
import 'interaction_batch3et_test.dart' show activate;
import 'interaction_batch3i_test.dart' show scopedApp;

class SceneReadPort extends TestRoomsPort implements PartyRoomsPreviewControl {
  final example = ExamplePartyRoomsAdapter();
  final sceneCalls = <(String, InteractionSource)>[];
  @override
  String get previewScene => example.previewScene;
  @override
  void selectPreviewScene(String scene) {
    sceneCalls.add((scene, currentStarBridgeActivationSource));
    example.selectPreviewScene(scene);
  }

  @override
  Future<RoomReadResult> read() async {
    reads++;
    return pending?.future ?? example.read();
  }

  @override
  Future<void> close() async {
    await super.close();
    await example.close();
  }
}

Finder refresh() => find.byKey(const Key('rooms-refresh'));
Finder sceneTrigger() => find.byKey(const Key('rooms-example-trigger'));
Finder sceneField() =>
    find.byWidgetPredicate((w) => w is StarBridgeSelectFormField<String>);
Future<void> openScene(WidgetTester t, String source) =>
    activate(t, sceneTrigger(), source);

class PageProbe {
  PageProbe(this.module, this.suite, {this.external});
  final PartyRoomsModule module;
  InteractionSuite suite;
  final VoidCallback? external;
  bool reduce = false, light = false, visible = true;
  late StateSetter update;
  Widget app() => StatefulBuilder(
    builder: (_, setState) {
      update = setState;
      return scopedApp(
        visible
            ? PartyRoomsPage(module: module, onRefresh: external)
            : const Text('away'),
        suite,
        reduce: reduce,
        light: light,
      );
    },
  );
}

Future<PageProbe> page(
  WidgetTester t,
  TestRoomsPort port,
  InteractionSuite suite, {
  VoidCallback? external,
}) async {
  size(t, const Size(1280, 1000));
  final module = PartyRoomsModule(port);
  addTearDown(module.dispose);
  await module.refresh();
  final probe = PageProbe(module, suite, external: external);
  await t.pumpWidget(probe.app());
  await t.pumpAndSettle();
  return probe;
}

void main() {
  setUpAll(loadFonts);
  for (final suite in InteractionSuite.values) {
    for (final source in ['pointer', 'keyboard', 'reader']) {
      testWidgets(
        '$suite actual room refresh $source retains content and retries original read',
        (t) async {
          final semantics = t.ensureSemantics();
          final port = TestRoomsPort();
          final p = await page(t, port, suite);
          try {
            final data = p.module.directory;
            final reads = port.reads;
            port.pending = Completer();
            await activate(t, refresh(), source);
            expect(p.module.manualRefreshing, isTrue);
            expect(port.reads, reads + 1);
            expect(p.module.directory, same(data));
            expect(find.byKey(const Key('rooms-directory')), findsOneWidget);
            expect(find.text('正在刷新…'), findsOneWidget);
            expect(
              t
                  .widget<StarBridgeActionButton>(
                    find.ancestor(
                      of: refresh(),
                      matching: find.byType(StarBridgeActionButton),
                    ),
                  )
                  .onActivate,
              isNull,
            );
            p.update(() {
              p.reduce = true;
              p.light = true;
            });
            await t.pumpAndSettle();
            expect(p.module.directory, same(data));
            port.pending!.complete(
              const RoomReadResult(RoomReadState.unavailable),
            );
            await t.pumpAndSettle();
            expect(p.module.state, RoomReadState.unavailable);
            expect(p.module.manualRefreshing, isFalse);
            expect(find.byKey(const Key('rooms-directory')), findsNothing);
            final copy = AppStrings.of(t.element(find.byType(PartyRoomsPage)))
                .text('rooms.error.unavailable');
            expect(find.text(copy), findsOneWidget);
            port.pending = Completer();
            await activate(t, refresh(), source);
            expect(port.reads, reads + 2);
            port.pending!.complete(ready(wire()));
            await t.pumpAndSettle();
            expect(p.module.state, RoomReadState.ready);
            expect(p.module.manualRefreshing, isFalse);
            expect(find.byKey(const Key('rooms-directory')), findsOneWidget);
            expect(t.takeException(), isNull);
          } finally {
            p.module.stopSession();
            await t.pumpWidget(const SizedBox());
            semantics.dispose();
          }
        },
      );
      testWidgets(
        '$suite native scene field $source drives only original example owner',
        (t) async {
          final semantics = t.ensureSemantics();
          final port = SceneReadPort();
          final p = await page(t, port, suite);
          try {
            expect(sceneField(), findsOneWidget);
            for (final scene in [
              'current',
              'host',
              'empty',
              'error',
              'directory',
            ]) {
              await openScene(t, source);
              await t.pumpAndSettle();
              await select(t, 'rooms-example', scene, source);
              await t.pumpAndSettle();
              expect(p.module.previewScene, scene);
              expect(port.sceneCalls.last, (
                scene,
                source == 'pointer'
                    ? InteractionSource.pointer
                    : InteractionSource.keyboard,
              ));
              expect(
                p.module.state,
                scene == 'error'
                    ? RoomReadState.unavailable
                    : RoomReadState.ready,
              );
              expect(
                find.byKey(ValueKey('rooms-example-$scene')),
                findsOneWidget,
              );
            }
            expect(port.sceneCalls, hasLength(5));
            expect(t.takeException(), isNull);
          } finally {
            p.module.stopSession();
            await t.pumpWidget(const SizedBox());
            semantics.dispose();
          }
        },
      );
    }
    testWidgets(
      '$suite external refresh retains each active callback and no fallback read',
      (t) async {
        final port = TestRoomsPort();
        final sources = <InteractionSource>[];
        final p = await page(
          t,
          port,
          suite,
          external: () => sources.add(currentStarBridgeActivationSource),
        );
        final reads = port.reads;
        for (var i = 0; i < 3; i++) {
          await activate(t, refresh(), 'pointer');
          await t.pump(const Duration(milliseconds: 25));
        }
        expect(sources, List.filled(3, InteractionSource.pointer));
        expect(port.reads, reads);
        expect(p.module.busy, isFalse);
        p.module.stopSession();
        await t.pumpWidget(const SizedBox());
      },
    );
    testWidgets(
      '$suite leaving during held read retains epoch late-response boundary',
      (t) async {
        final port = TestRoomsPort();
        final p = await page(t, port, suite);
        final data = p.module.directory;
        port.pending = Completer();
        await activate(t, refresh(), 'keyboard');
        expect(p.module.manualRefreshing, isTrue);
        p.update(() => p.visible = false);
        await t.pumpAndSettle();
        expect(p.module.busy, isFalse);
        port.pending!.complete(ready(wire(rooms: [])));
        await t.pumpAndSettle();
        expect(p.module.directory, same(data));
        expect(find.byType(PartyRoomsPage), findsNothing);
        p.module.stopSession();
        await t.pumpWidget(const SizedBox());
        expect(t.takeException(), isNull);
      },
    );
    testWidgets(
      '$suite external read retires scene menu and departure ignores late result',
      (t) async {
        final port = SceneReadPort();
        final p = await page(t, port, suite);
        final data = p.module.directory;
        final field = t.state<FormFieldState<String>>(sceneField());
        await openScene(t, 'pointer');
        await t.pump(const Duration(milliseconds: 40));
        port.pending = Completer();
        final reading = p.module.refresh();
        await t.pumpAndSettle();
        expect(
          find.byKey(const ValueKey<Object>(('rooms-example', 'empty'))),
          findsNothing,
        );
        expect(t.state<FormFieldState<String>>(sceneField()), same(field));
        expect(field.value, 'directory');
        expect(port.sceneCalls, isEmpty);
        p.update(() => p.visible = false);
        await t.pumpAndSettle();
        port.pending!.complete(ready(wire(rooms: [])));
        await reading;
        await t.pumpAndSettle();
        expect(p.module.directory, same(data));
        expect(p.module.previewScene, 'directory');
        p.module.stopSession();
        await t.pumpWidget(const SizedBox());
        expect(t.takeException(), isNull);
      },
    );
    testWidgets(
      '$suite scene cancel live settings and pending read keep original gate',
      (t) async {
        final port = SceneReadPort();
        final p = await page(t, port, suite);
        await openScene(t, 'pointer');
        await t.pump(const Duration(milliseconds: 30));
        p.update(() {
          p.reduce = true;
          p.light = true;
        });
        await t.pumpAndSettle();
        await t.sendKeyEvent(LogicalKeyboardKey.escape);
        await t.pumpAndSettle();
        expect(port.sceneCalls, isEmpty);
        expect(p.module.previewScene, 'directory');
        final data = p.module.directory;
        port.pending = Completer();
        await openScene(t, 'keyboard');
        await t.pumpAndSettle();
        await select(t, 'rooms-example', 'empty', 'keyboard');
        await t.pumpAndSettle();
        expect(p.module.busy, isTrue);
        expect(p.module.manualRefreshing, isFalse);
        expect(p.module.directory, same(data));
        expect(
          t.widget<StarBridgeSelectFormField<String>>(sceneField()).onChanged,
          isNull,
        );
        expect(port.sceneCalls, [('empty', InteractionSource.keyboard)]);
        port.pending!.complete(await port.example.read());
        await t.pumpAndSettle();
        expect(p.module.directory!.rooms, isEmpty);
        expect(p.module.busy, isFalse);
        p.module.stopSession();
        await t.pumpWidget(const SizedBox());
        expect(t.takeException(), isNull);
      },
    );
  }
}
