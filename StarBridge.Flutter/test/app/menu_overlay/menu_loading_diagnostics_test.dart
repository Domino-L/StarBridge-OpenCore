import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/diagnostics/loading_diagnostics.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_overlay_surface_app.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_bridge_preview.dart';
import 'package:starbridge_flutter/platform/window/method_channel_menu_preview_window.dart';
import 'package:starbridge_flutter/shared/diagnostics/loading_metrics.dart';

import 'menu_overlay_surface_app_test.dart' as surface;
import 'menu_overlay_workspace_test.dart' as workspace;
import '../../features/friends/social_layout_test.dart' show size;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('menu uses a separate opt-in auxiliary trace', () {
    expect(
      LoadingDiagnostics.auxiliaryTracePath(const {
        'STARBRIDGE_LOADING_TRACE_PATH': r'C:\trace.jsonl',
      }, LoadingAuxiliarySurface.menu),
      r'C:\trace.jsonl.menu.jsonl',
    );
  });

  test('menu lifecycle accepts only fixed state names and numeric facts', () {
    final rows = <Map<String, Object>>[];
    final metrics = LoadingMetrics(nowUs: () => 1, write: rows.add);
    metrics.auxiliaryLifecycle(
      LoadingAuxiliarySurface.menu,
      state: 'inactive',
      framesEnabled: true,
    );
    metrics.auxiliaryLifecycle(
      LoadingAuxiliarySurface.menu,
      state: 'private-state-token',
      framesEnabled: false,
    );
    expect(rows, [
      {
        'us': 1,
        'kind': 'auxiliaryLifecycle',
        'surface': 'menu',
        'state': 'inactive',
        'framesEnabled': true,
      },
    ]);
  });

  test('drag updates coalesce until build and require matching raster', () {
    var time = 10;
    final rows = <Map<String, Object>>[];
    final metrics = LoadingMetrics(nowUs: () => time, write: rows.add);
    metrics.route('/menu');
    metrics.menuDragUpdate(resize: false);
    time = 20;
    metrics.menuDragUpdate(resize: true);
    time = 30;
    metrics.menuDragBuilt();
    final built = rows.singleWhere((row) => row['kind'] == 'menuDragBuild');
    expect(built['updates'], 2);
    expect(built['resizeUpdates'], 1);
    expect(built['firstHandledUs'], 10);
    expect(built['lastHandledUs'], 20);
    expect(rows.where((row) => row['kind'] == 'menuDragRaster'), isEmpty);
    metrics.frame(buildUs: 1, rasterUs: 1, totalUs: 2);
    metrics.frame(
      buildUs: 10,
      rasterUs: 10,
      totalUs: 30,
      buildStartUs: 25,
      buildFinishUs: 35,
      rasterFinishUs: 50,
    );
    final raster = rows.singleWhere((row) => row['kind'] == 'menuDragRaster');
    expect(raster['firstHandledToRasterUs'], 40);
    expect(raster['lastHandledToRasterUs'], 30);
    metrics.frame(
      buildUs: 10,
      rasterUs: 10,
      totalUs: 30,
      buildStartUs: 25,
      buildFinishUs: 35,
      rasterFinishUs: 50,
    );
    expect(rows.where((row) => row['kind'] == 'menuDragRaster'), hasLength(1));
  });

  test('hide, missing frames, and stop cannot fabricate drag raster', () {
    var time = 10;
    final rows = <Map<String, Object>>[];
    final metrics = LoadingMetrics(nowUs: () => time, write: rows.add);
    metrics.route('/menu');
    metrics.menuDragUpdate(resize: false);
    time = 20;
    metrics.menuDragBuilt();
    metrics.menuSurface(opening: 1, wanted: false);
    metrics.frame(
      buildUs: 10,
      rasterUs: 10,
      totalUs: 30,
      buildStartUs: 15,
      buildFinishUs: 25,
      rasterFinishUs: 30,
    );
    metrics.route('/menu');
    metrics.menuDragUpdate(resize: false);
    time = 40;
    metrics.menuDragBuilt();
    metrics.frame(
      buildUs: 10,
      rasterUs: 10,
      totalUs: 30,
      buildStartUs: 45,
      buildFinishUs: 55,
      rasterFinishUs: 60,
    );
    metrics.stop();
    metrics.menuDragUpdate(resize: false);
    metrics.menuDragBuilt();
    expect(rows.where((row) => row['kind'] == 'menuDragRaster'), isEmpty);
    expect(rows.where((row) => row['kind'] == 'menuDragBuild'), hasLength(2));
  });

  testWidgets('accepted menu snapshots paint without recording labels', (
    tester,
  ) async {
    size(tester, const Size(1280, 900));
    final rows = <Map<String, Object>>[];
    final metrics = LoadingMetrics(nowUs: () => 10, write: rows.add);
    Future<T> measured<T>(Future<T> Function() body) =>
        runZoned(body, zoneValues: {loadingMetricsZoneKey: metrics});
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      surface.channel,
      (call) async => null,
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        surface.channel,
        null,
      ),
    );
    await measured(() => tester.pumpWidget(const MenuOverlaySurfaceApp()));
    await measured(
      () => surface.push(tester, {
        ...surface.snapshot(1),
        'contextLabel': 'private-display-token',
      }),
    );
    await measured(() => tester.pumpAndSettle());
    expect(rows.where((row) => row['kind'] == 'route'), hasLength(1));
    expect(rows.where((row) => row['kind'] == 'contentPaint'), hasLength(1));
    expect(rows.where((row) => row['kind'] == 'contentRaster'), isEmpty);
    await measured(
      () => surface.push(tester, surface.snapshot(1, wanted: false)),
    );
    await measured(() => surface.push(tester, surface.snapshot(1)));
    expect(rows.where((row) => row['kind'] == 'route'), hasLength(1));
    await measured(() => surface.push(tester, surface.snapshot(2)));
    await measured(() => tester.pumpAndSettle());
    expect(rows.where((row) => row['kind'] == 'route'), hasLength(2));
    expect(rows.toString(), isNot(contains('private-display-token')));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('real workspace drag emits build samples with no coordinates', (
    tester,
  ) async {
    size(tester, const Size(1280, 720));
    final fixture = workspace.Fixture()..controller.open('friends');
    var time = 1;
    final rows = <Map<String, Object>>[];
    final metrics = LoadingMetrics(nowUs: () => time++, write: rows.add)
      ..route('/menu');
    Future<T> measured<T>(Future<T> Function() body) =>
        runZoned(body, zoneValues: {loadingMetricsZoneKey: metrics});
    await measured(() => tester.pumpWidget(fixture.view()));
    await measured(() => tester.pumpAndSettle());
    final before = tester.getRect(workspace.keyed('menu-panel-friends'));
    await measured(
      () => tester.drag(
        workspace.keyed('menu-move-friends'),
        const Offset(100, 60),
      ),
    );
    await measured(() => tester.pumpAndSettle());
    expect(
      tester.getRect(workspace.keyed('menu-panel-friends')).left,
      greaterThan(before.left),
    );
    expect(rows.where((row) => row['kind'] == 'menuDragBuild'), isNotEmpty);
    expect(rows.where((row) => row['kind'] == 'menuDragRaster'), isEmpty);
    expect(rows.toString(), isNot(contains('friends')));
    expect(rows.expand((row) => row.keys), isNot(contains('x')));
    expect(rows.expand((row) => row.keys), isNot(contains('y')));
    await tester.pumpWidget(const SizedBox());
    fixture.controller.dispose();
  });

  testWidgets('trace stopping preserves the mounted menu workspace', (
    tester,
  ) async {
    size(tester, const Size(1280, 900));
    final metrics = LoadingMetrics(nowUs: () => 10, write: (_) {});
    Future<T> measured<T>(Future<T> Function() body) =>
        runZoned(body, zoneValues: {loadingMetricsZoneKey: metrics});
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      surface.channel,
      (call) async => null,
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        surface.channel,
        null,
      ),
    );
    await measured(
      () => tester.pumpWidget(
        const MenuOverlaySurfaceApp(workspacePreview: true),
      ),
    );
    await measured(() => surface.push(tester, surface.snapshot(1)));
    await measured(() => tester.pumpAndSettle());
    final before = tester.state(find.byType(MenuBridgePreview));
    metrics.stop();
    await measured(() => surface.push(tester, surface.snapshot(1)));
    await measured(() => tester.pumpAndSettle());
    expect(
      identical(tester.state(find.byType(MenuBridgePreview)), before),
      true,
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('primary timing keeps request separate from native generation', (
    tester,
  ) async {
    const channel = MethodChannel('starbridge/menu-primary');
    final messenger = tester.binding.defaultBinaryMessenger;
    final rows = <Map<String, Object>>[];
    final metrics = LoadingMetrics(nowUs: () => 10, write: rows.add);
    Future<T> measured<T>(Future<T> Function() body) =>
        runZoned(body, zoneValues: {loadingMetricsZoneKey: metrics});
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method != 'preview') return null;
      final request = (call.arguments as Map)['request'];
      await messenger.handlePlatformMessage(
        channel.name,
        const StandardMethodCodec().encodeMethodCall(
          MethodCall('state', {'request': request, 'state': 'visible'}),
        ),
        (_) {},
      );
      return 37;
    });
    final port = MethodChannelMenuPreviewWindow(lifetime: MenuWindowLifetime());
    expect(
      await measured(
        () => port.open(
          contextLabel: 'private-title',
          returnLabel: 'Return',
          settingsLabel: 'Settings',
        ),
      ),
      true,
    );
    final phases = rows.where((row) => row['kind'] == 'menuOpening').toList();
    expect(
      phases.map((row) => row['phase']),
      containsAllInOrder([
        'request',
        'preferencesFinished',
        'recoveryFinished',
        'hostReportFinished',
        'nativeRequest',
        'visible',
        'nativeReply',
        'settled',
      ]),
    );
    expect(
      phases.singleWhere((row) => row['phase'] == 'nativeReply')['opening'],
      37,
    );
    expect(phases.map((row) => row['request']).toSet(), {1});
    expect(rows.toString(), isNot(contains('private-title')));
    port.dispose();
    await tester.pump();
    messenger.setMockMethodCallHandler(channel, null);
  });
}
