import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_scene_picker.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_scene_controller.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_scene_projection.dart';
import 'package:starbridge_flutter/features/overlay_settings/bridge_overlay_scenes.dart';

const initial = OverlaySceneState(
  available: true,
  status: 'standby',
  targets: [OverlaySceneTarget('A', '组织'), OverlaySceneTarget('B', '组织')],
);
void main() {
  test(
    'page focus is coalesced, account scoped and never a manual selection',
    () async {
      final port = _Port();
      final controller = OverlaySceneController(port, autoStart: false);
      addTearDown(controller.dispose);
      await controller.refresh();
      await controller.select('org:A');
      final late = Completer<OverlaySceneState>();
      port.readResult = () => late.future;
      final reading = controller.refresh();
      controller.focusCommunity('A');
      controller.focusCommunity('B');
      controller.focusCommunity('B');
      late.complete(port.state);
      await reading;
      await Future<void>.delayed(Duration.zero);
      expect(port.focused, ['B']);
      expect(port.writes, 1);
      expect(controller.projection.value.code, 'A');
      expect(controller.projection.value.mode, 'community');
      port.readResult = null;
      port.events.add(null);
      await Future<void>.delayed(Duration.zero);
      await controller.refresh();
      expect(port.focused, ['B']);
      controller.focusCommunity('B');
      await Future<void>.delayed(Duration.zero);
      expect(port.focused, ['B', 'B']);
    },
  );
  test(
    'confirmed rename survives a late scene read without changing selection',
    () async {
      final port = _Port();
      final controller = OverlaySceneController(port, autoStart: false);
      addTearDown(controller.dispose);
      await controller.refresh();
      await controller.select('org:A');
      final late = Completer<OverlaySceneState>();
      port.readResult = () => late.future;
      final reading = controller.refresh();
      controller.renameCommunity('A', '新名称');
      expect(controller.projection.value.targets.first.name, '新名称');
      late.complete(port.state);
      await reading;
      expect(controller.projection.value.targets.first.name, '新名称');
      expect(controller.projection.value.targets.last.name, '组织');
      expect(controller.projection.value.code, 'A');
      expect(controller.projection.value.revision, port.state.revision);
      expect(port.writes, 1);
    },
  );
  testWidgets(
    'narrow picker fits long organization names and saves exact target',
    (tester) async {
      final port = _Port();
      port.state = OverlaySceneState(
        available: true,
        status: 'standby',
        targets: [OverlaySceneTarget('A', 'Very long organization name ' * 12)],
      );
      final controller = OverlaySceneController(port, autoStart: false);
      addTearDown(controller.dispose);
      await controller.refresh();
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: const [AppStringsDelegate()],
          home: Scaffold(
            body: SizedBox(
              width: 320,
              child: OverlayScenePicker(controller: controller),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), null);
      await tester.tap(find.byKey(const Key('overlay-source-picker')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Very long organization name ' * 12).last);
      await tester.pumpAndSettle();
      expect(port.writes, 1);
      expect(controller.projection.value.code, 'A');
      expect(tester.takeException(), null);
    },
  );
  test(
    'same-name organizations use identity; fleet and unknown targets disabled',
    () async {
      final port = _Port();
      final controller = OverlaySceneController(port, autoStart: false);
      addTearDown(controller.dispose);
      await controller.refresh();
      expect(await controller.select('fleet'), false);
      expect(await controller.select('org:unknown'), false);
      expect(port.writes, 0);
      expect(await controller.select('org:B'), true);
      expect(controller.projection.value.code, 'B');
      final view = projectOverlayScene(controller.projection.value);
      expect(view.optionById('fleet')!.enabled, false);
      expect(view.optionById('org:B')!.label, '组织');
    },
  );
  test(
    'account invalidation rejects late reads and clears selection',
    () async {
      final port = _Port();
      final controller = OverlaySceneController(port, autoStart: false);
      addTearDown(controller.dispose);
      final late = Completer<OverlaySceneState>();
      port.readResult = () => late.future;
      final reading = controller.refresh();
      port.readResult = () async =>
          const OverlaySceneState(status: 'signedOut');
      port.events.add(null);
      await Future<void>.delayed(Duration.zero);
      late.complete(
        const OverlaySceneState(mode: 'community', code: 'B', available: true),
      );
      await reading;
      expect(controller.projection.value.status, 'signedOut');
      expect(controller.projection.value.code, null);
    },
  );
  test('uncertain write reads back without replaying write', () async {
    final port = _Port();
    final controller = OverlaySceneController(port, autoStart: false);
    addTearDown(controller.dispose);
    await controller.refresh();
    port.failWrite = true;
    expect(await controller.select('org:B'), false);
    await Future<void>.delayed(Duration.zero);
    expect(port.writes, 1);
    expect(controller.projection.value.code, 'B');
    expect(controller.projection.value.failure, false);
  });
  test(
    'missing chosen organization stays selected and never falls through',
    () {
      final view = projectOverlayScene(
        const OverlaySceneState(
          mode: 'community',
          code: 'B',
          available: true,
          status: 'unavailable',
          targets: [OverlaySceneTarget('A', 'Other')],
        ),
      );
      expect(view.preferredSceneId, 'org:B');
      expect(view.actualSceneId, null);
      expect(view.optionById('org:B')!.enabled, false);
    },
  );
  test(
    'bridge snapshot rejects duplicate targets and unknown actual source',
    () {
      final payload = <String, Object?>{
        'schemaVersion': 1,
        'revision': 1,
        'mode': 'community',
        'code': 'B',
        'actualId': null,
        'status': 'standby',
        'organizations': [
          {'code': 'B', 'name': '组织'},
        ],
      };
      expect(BridgeOverlayScenes.parse(payload).code, 'B');
      expect(
        () => BridgeOverlayScenes.parse({...payload, 'actualId': 'org:A'}),
        throwsFormatException,
      );
      expect(
        () => BridgeOverlayScenes.parse({
          ...payload,
          'organizations': [
            {'code': 'B', 'name': 'a'},
            {'code': 'B', 'name': 'b'},
          ],
        }),
        throwsFormatException,
      );
    },
  );
}

class _Port implements OverlayScenePort {
  final focused = <String>[];
  @override
  Future<OverlaySceneState> focusCommunity(String code) async {
    focused.add(code);
    return state;
  }

  final events = StreamController<void>.broadcast();
  OverlaySceneState state = initial;
  Future<OverlaySceneState> Function()? readResult;
  int writes = 0;
  bool failWrite = false;
  @override
  Stream<void> get invalidations => events.stream;
  @override
  Future<OverlaySceneState> read() => readResult?.call() ?? Future.value(state);
  @override
  Future<OverlaySceneState> select(
    int revision,
    String mode,
    String? code,
  ) async {
    writes++;
    state = OverlaySceneState(
      revision: revision + 1,
      mode: mode,
      code: code,
      targets: initial.targets,
      available: true,
      status: 'standby',
    );
    if (failWrite) throw StateError('Uncertain response');
    return state;
  }

  @override
  void close() {
    unawaited(events.close());
  }
}
