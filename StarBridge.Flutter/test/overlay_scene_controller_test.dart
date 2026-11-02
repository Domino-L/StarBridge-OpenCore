import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/app/shell/chrome/overlay_source_labels.dart';
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
  test('a plan-fixed source offers follow first and never writes a session or account choice', () async {
    final port = _Port();
    OverlaySceneState state({required bool bound}) => OverlaySceneState(
      available: true, status: 'ready', sourceOwnerKey: 'A' * 64,
      presetBindingId: bound ? 'room' : null,
      actualId: bound ? 'room' : 'org:A', targets: initial.targets,
    );
    port.state = state(bound: true);
    final controller = OverlaySceneController(port, autoStart: false);
    addTearDown(controller.dispose);
    var released = 0;
    controller.followShared = () async {
      released++;
      port.state = state(bound: false);
      return true;
    };
    await controller.refresh();
    final strings = AppStrings.resolve(const Locale('zh', 'CN'));
    final bound = projectOverlayScene(controller.projection.value);
    expect(overlaySourceLabel(bound, strings), '方案固定：当前房间');
    expect(overlaySourceHint(bound), 'overlay.source.planFixedHint');
    expect(bound.options.first.id, 'followShared');
    expect(bound.options.where((o) => o.enabled).map((o) => o.id), ['followShared']);
    expect(await controller.select('auto'), isFalse);
    expect(port.writes, 0);
    expect(await controller.select('followShared'), isTrue);
    expect(released, 1);
    expect(port.writes, 0);
    final free = projectOverlayScene(controller.projection.value);
    expect(free.options.any((o) => o.id == 'followShared'), isFalse);
    expect(overlaySourceLabel(free, strings), '自动 · 组织');
    expect(overlaySourceHint(free), 'overlay.source.hint');
  });

  test('a leftover session source without a fixed plan source still reads and never blocks a choice', () async {
    // Field report 2026-10-21: after "follow" on the same plan, a leftover
    // session source made every read invalid, so the card showed "unavailable".
    final state = BridgeOverlayScenes.parse({
      'schemaVersion': 1, 'revision': 3, 'mode': 'community', 'code': 'A',
      'actualId': 'org:A', 'status': 'ready', 'sourceOwnerKey': 'a' * 64,
      'presetBindingId': null, 'temporarySourceId': 'room',
      'resolvedSourceIds': {'auto': 'org:A', 'room': null, 'org:A': 'org:A'},
      'organizations': [{'code': 'A', 'name': '组织'}],
    });
    expect(state.status, 'ready');
    expect(state.actualId, 'org:A');
    expect(state.resolvedSourceIds!['org:A'], 'org:A');
    final port = _Port()..state = const OverlaySceneState(
      available: true, status: 'ready', temporarySourceId: 'room', targets: [OverlaySceneTarget('A', '组织')],
    );
    final controller = OverlaySceneController(port, autoStart: false);
    addTearDown(controller.dispose);
    await controller.refresh();
    expect(await controller.select('org:A'), isTrue);
    expect(port.writes, 1);
    expect(() => BridgeOverlayScenes.parse({
      'schemaVersion': 1, 'revision': 3, 'mode': 'auto', 'actualId': null, 'status': 'ready',
      'temporarySourceId': 'room', 'organizations': [],
    }), throwsFormatException, reason: 'a session source still needs an owner scope');
  });

  test('a late follow cannot publish after account invalidation', () async {
    final port = _Port()..state = const OverlaySceneState(available: true, presetBindingId: 'room');
    final controller = OverlaySceneController(port, autoStart: false);
    addTearDown(controller.dispose);
    await controller.refresh();
    final pending = Completer<bool>();
    controller.followShared = () => pending.future;
    final selecting = controller.select('followShared');
    port.state = const OverlaySceneState(status: 'signedOut');
    port.events.add(null);
    await Future<void>.delayed(Duration.zero);
    pending.complete(true);
    expect(await selecting, isFalse);
    expect(controller.projection.value.status, 'signedOut');
    expect(port.writes, 0);
  });

  test('manual selection supersedes a pending background read', () async {
    final port = _Port();
    final controller = OverlaySceneController(port, autoStart: false);
    addTearDown(controller.dispose);
    await controller.refresh();
    final late = Completer<OverlaySceneState>();
    port.readResult = () => late.future;
    final reading = controller.refresh();
    try {
      expect(await controller.select('room'), true);
      expect(port.writes, 1);
    } finally {
      late.complete(initial);
      await reading;
    }
    expect(controller.projection.value.mode, 'room');
  });
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
    'same-name organizations use identity; unsupported fleet and unknown targets unavailable',
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
      expect(view.optionById('fleet'), isNull, reason: 'Host without main fleet');
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
  test(
    'a missed background read keeps the last answer until misses repeat',
    () async {
      final port = _Port();
      final controller = OverlaySceneController(port, autoStart: false);
      addTearDown(controller.dispose);
      await controller.refresh();
      port.readResult = () => Future.error(StateError('timeout'));
      await controller.refresh();
      await controller.refresh();
      expect(controller.projection.value.status, 'standby');
      expect(controller.projection.value.failure, false);
      await controller.refresh();
      expect(controller.projection.value.failure, true);
      expect(controller.projection.value.status, 'unavailable');
      port.readResult = null;
      await controller.refresh();
      expect(controller.projection.value.failure, false);
      port.readResult = () => Future.error(StateError('timeout'));
      await controller.refresh();
      expect(
        controller.projection.value.failure,
        false,
        reason: 'a good read restarts the count',
      );
    },
  );
  test('the main fleet is offered only by a Host that can show it', () async {
    final port = _Port();
    final controller = OverlaySceneController(port, autoStart: false);
    addTearDown(controller.dispose);
    await controller.refresh();
    expect(
      projectOverlayScene(controller.projection.value).options.map((o) => o.id),
      isNot(contains('fleet')),
    );
    expect(await controller.select('fleet'), isFalse);
    expect(port.writes, 0);

    port.state = const OverlaySceneState(
      available: true,
      status: 'standby',
      fleetStatus: 'ready',
      fleetName: 'Domino Pizza',
      targets: [OverlaySceneTarget('A', '组织')],
    );
    await controller.refresh();
    final view = projectOverlayScene(controller.projection.value);
    final fleet = view.options.singleWhere((o) => o.id == 'fleet');
    expect(fleet.enabled, isTrue);
    expect(fleet.label, 'Domino Pizza', reason: 'listed by its own name');
    expect(
      view.options.map((o) => o.id).toList(),
      ['auto', 'room', 'fleet', 'org:A'],
      reason: 'the main fleet sits with the organizations',
    );
    expect(await controller.select('fleet'), isTrue);
    expect(controller.projection.value.mode, 'fleet');
    expect(controller.projection.value.code, isNull);
    expect(controller.projection.value.preferredId, 'fleet');
  });
  test('a main fleet the viewer is not in is simply not listed', () {
    final left = projectOverlayScene(
      const OverlaySceneState(
        available: true,
        status: 'ready',
        mode: 'fleet',
        fleetStatus: 'notMember',
      ),
    );
    expect(
      const OverlaySceneState(fleetStatus: 'unavailable').offersFleet,
      isFalse,
      reason: 'a failed read without a confirmed name offers nothing',
    );
    final entry = left.options.singleWhere((o) => o.id == 'fleet');
    expect(entry.enabled, isFalse);
    expect(
      entry.labelKey,
      'overlay.source.missing',
      reason: 'a fixed choice reads like an unavailable organization',
    );
    final never = projectOverlayScene(
      const OverlaySceneState(
        available: true,
        status: 'ready',
        fleetStatus: 'notMember',
      ),
    );
    expect(never.options.map((o) => o.id), isNot(contains('fleet')));
  });
  test('the main fleet page and organization pages take turns as the page', () async {
    final port = _Port();
    final controller = OverlaySceneController(port, autoStart: false);
    addTearDown(controller.dispose);
    await controller.refresh();
    controller.focusFleet();
    await Future<void>.delayed(Duration.zero);
    controller.focusFleet();
    await Future<void>.delayed(Duration.zero);
    controller.focusCommunity('A');
    await Future<void>.delayed(Duration.zero);
    controller.focusFleet();
    await Future<void>.delayed(Duration.zero);
    expect(port.focused, ['fleet', 'A', 'fleet']);
    expect(port.writes, 0, reason: 'page focus is never a saved choice');
  });
}

class _Port implements OverlayScenePort {
  final focused = <String>[];
  @override
  Future<OverlaySceneState> focusCommunity(String code) async {
    focused.add(code);
    return state;
  }

  @override
  Future<OverlaySceneState> focusFleet() async {
    focused.add('fleet');
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
      fleetStatus: state.fleetStatus,
    );
    if (failWrite) throw StateError('Uncertain response');
    return state;
  }

  @override
  void close() {
    unawaited(events.close());
  }
}
