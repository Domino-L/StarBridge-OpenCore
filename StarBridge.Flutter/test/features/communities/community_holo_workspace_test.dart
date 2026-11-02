import '../../_support/development_fixture_path.dart';

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_wheel_gate.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/design_system/styles/future_restraint_style.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/common/organization_member_row.dart';
import 'package:starbridge_flutter/features/communities/community_workspace_port.dart';
import 'package:starbridge_flutter/features/communities/community_workspace_view.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_holo_header.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_workspace_header.dart';

import 'community_image_test_support.dart';
import 'community_workspace_test.dart';
import '../friends/social_layout_test.dart' show loadFonts;
import '../official_fleet/official_fleet_holo_header_test.dart' show blankPoint;

final _capture = Platform.environment['STARBRIDGE_CAPTURE_HOLO'] == '1';
final _previews = developmentFixturePath('StarBridge-DesignPreviews/MainFleetBanner');

Future<Uint8List> _banner() async {
  final asset = File('$_previews/assets/banner-default.jpg');
  if (_capture && asset.existsSync()) return asset.readAsBytesSync();
  final recorder = ui.PictureRecorder();
  const rect = Rect.fromLTWH(0, 0, 900, 300);
  Canvas(recorder).drawRect(
    rect,
    Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFF203040), Color(0xFF7FD0FF)],
      ).createShader(rect),
  );
  final image = await recorder.endRecording().toImage(900, 300);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data!.buffer.asUint8List();
}

Future<void> _shot(WidgetTester tester, String name) async {
  if (!_capture) return;
  await tester.runAsync(() async {
    final boundary = tester.renderObject(
      find.byKey(const ValueKey('community-holo')),
    ) as RenderRepaintBoundary;
    final image = await boundary.toImage();
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    await Directory('build/reviews').create(recursive: true);
    await File('build/reviews/holo-community-$name.png')
        .writeAsBytes(data!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  setUpAll(() async {
    if (!_capture) return;
    await loadFonts();
    await (FontLoader('Source Code Pro')
          ..addFont(rootBundle.load('assets/fonts/SourceCodeVF-Upright.ttf')))
        .load();
  });

  testWidgets('a joined community uses the main fleet two-screen shell', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(2048, 1152);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final banner = await tester.runAsync(_banner);
    final port = WorkspaceTestPort();
    addTearDown(port.changes.close);
    port.reader = (target, query, _) async => CommunityWorkspace.parse(
      workspacePayload(target: target, query: query)
        ..['name'] = '北辰联合舰队'
        ..['code'] = 'NRTH'
        ..['hasBanner'] = true,
    );
    port.mediaReader = (offset, _) async =>
        mediaChunk(banner!, offset, kind: 'banner');
    final theme = buildStarBridgeTheme(
      FutureRestraintStyle.resolve(AppearanceMode.dark),
      const Locale('zh', 'CN'),
    );
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'CN'),
        supportedLocales: AppStrings.supportedLocales,
        localizationsDelegates: const [
          AppStringsDelegate(),
          ...GlobalMaterialLocalizations.delegates,
        ],
        theme: theme,
        home: Scaffold(
          body: RepaintBoundary(
            key: const ValueKey('community-holo'),
            child: CommunityWorkspaceView(
              port: port,
              targetRef: 'a' * 32,
              holo: true,
              actions: const SizedBox.shrink(),
            ),
          ),
        ),
      ),
    );
    await settleCommunityImages(tester);
    await tester.pumpAndSettle();
    // Upper screen: the holo header with the community's name and code.
    expect(find.byType(OfficialFleetHoloHeader), findsOneWidget);
    expect(find.text('北辰联合舰队'), findsWidgets);
    await _shot(tester, 'upper');

    // Entering members moves to the lower screen: the bar and the member
    // board in the glass surface.
    await tester.tap(find.byKey(const Key('official-fleet-tab-members')));
    await tester.pumpAndSettle();
    expect(find.byType(OfficialFleetHoloBar), findsOneWidget);
    expect(find.byType(OrganizationMemberRow), findsOneWidget);
    await _shot(tester, 'lower');

    // The bar's expand control goes back up.
    await tester.tap(find.byKey(const Key('organization-holo-expand')));
    await tester.pumpAndSettle();
    expect(find.byType(OfficialFleetHoloHeader), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  // 2026-10-24: blank parts of a screen hit-test through to the backdrop. The
  // shell's wheel listener must still receive the wheel there.
  group('wheel on blank parts of a screen', () {
    final upper = find.byKey(const ValueKey('official-fleet-upper-screen'));
    final bar = find.byType(OfficialFleetHoloBar);

    testWidgets('a wheel down on blank upper screen goes to the lower one', (
      tester,
    ) async {
      await _pumpShell(tester);
      final mouse = TestPointer(1, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(mouse.hover(blankPoint(tester, upper)));
      await tester.sendEventToBinding(mouse.scroll(const Offset(0, 120)));
      await tester.pumpAndSettle();
      expect(bar, findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('up in the list scrolls it; only the top returns upward', (
      tester,
    ) async {
      await _pumpShell(tester, crew: 20);
      final mouse = TestPointer(1, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(mouse.hover(blankPoint(tester, upper)));
      await tester.sendEventToBinding(mouse.scroll(const Offset(0, 120)));
      await tester.pumpAndSettle();
      expect(bar, findsOneWidget);
      final row = find.byType(OrganizationMemberRow).first;
      ScrollPosition position() => tester
          .state<ScrollableState>(
            find.ancestor(of: row, matching: find.byType(Scrollable)).first,
          )
          .position;
      await tester.sendEventToBinding(
        mouse.hover(tester.getBottomLeft(bar) + const Offset(300, 240)),
      );
      for (var i = 0; i < 3; i++) {
        await tester.sendEventToBinding(mouse.scroll(const Offset(0, 120)));
        await tester.pumpAndSettle();
      }
      expect(position().pixels, greaterThan(200));
      await tester.sendEventToBinding(mouse.scroll(const Offset(0, -120)));
      await tester.pumpAndSettle();
      expect(bar, findsOneWidget, reason: 'Not at the top: list only');
      expect(position().pixels, greaterThan(0));
      var ups = 0;
      var wheelTime = Duration.zero;
      OfficialFleetWheelGate.debugNow = () => wheelTime;
      addTearDown(() => OfficialFleetWheelGate.debugNow = null);
      while (bar.evaluate().isNotEmpty && ups < 20) {
        wheelTime += const Duration(milliseconds: 500);
        final atTop = position().pixels == 0;
        await tester.sendEventToBinding(mouse.scroll(const Offset(0, -120)));
        await tester.pumpAndSettle();
        ups++;
        if (bar.evaluate().isEmpty) {
          expect(atTop, isTrue, reason: 'Switched before the list top');
        }
      }
      expect(bar, findsNothing, reason: 'Up at the top returns');
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('upper screen buttons still take clicks', (tester) async {
      await _pumpShell(tester);
      await tester.tap(find.byKey(const Key('organization-holo-collapse')));
      await tester.pumpAndSettle();
      expect(bar, findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  });
}

Future<void> _pumpShell(WidgetTester tester, {int crew = 1}) async {
  tester.view.physicalSize = const Size(1600, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final banner = await tester.runAsync(_banner);
  final port = WorkspaceTestPort();
  addTearDown(port.changes.close);
  port.reader = (target, query, _) async {
    final payload = workspacePayload(target: target, query: query)
      ..['hasBanner'] = true;
    final member = (payload['members']! as List).single as Map;
    payload['members'] = [
      for (var i = 0; i < crew; i++)
        {
          ...member,
          'memberRef': i.toRadixString(16).padLeft(32, 'c'),
          'callsign': 'Pilot$i',
          'isSelf': i == 0,
        },
    ];
    payload['totalCount'] = crew;
    payload['matchedCount'] = crew;
    return CommunityWorkspace.parse(payload);
  };
  port.mediaReader = (offset, _) async =>
      mediaChunk(banner!, offset, kind: 'banner');
  final theme = buildStarBridgeTheme(
    FutureRestraintStyle.resolve(AppearanceMode.dark),
    const Locale('zh', 'CN'),
  );
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('zh', 'CN'),
      supportedLocales: AppStrings.supportedLocales,
      localizationsDelegates: const [
        AppStringsDelegate(),
        ...GlobalMaterialLocalizations.delegates,
      ],
      theme: theme,
      home: Scaffold(
        body: CommunityWorkspaceView(
          port: port,
          targetRef: 'a' * 32,
          holo: true,
          actions: const SizedBox.shrink(),
        ),
      ),
    ),
  );
  await settleCommunityImages(tester);
  await tester.pumpAndSettle();
}
