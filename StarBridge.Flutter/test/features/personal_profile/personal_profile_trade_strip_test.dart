import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/styles/future_restraint_style.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_trade_strip.dart';

import '../friends/social_layout_test.dart' show loadFonts;
import 'profile_polish_regression_test.dart' show app;

const _full = ProfileTradeStripData(
  localDays: [true, true, true, true, true, false, false],
  localWindow: '19:30–23:00',
  openNow: true,
  contact: 'Discord',
  reputation: '★ 128 · 已成交 31',
);

Widget _host(Widget strip, AppearanceMode mode, {double width = 1000}) => RepaintBoundary(
  key: const Key('shot'),
  child: app(
    Theme(
      data: buildStarBridgeTheme(
        FutureRestraintStyle.resolve(mode),
        const Locale('zh', 'CN'),
      ),
      child: Builder(
        builder: (context) => Container(
          width: width,
          padding: const EdgeInsets.all(24),
          color: Theme.of(context).colorScheme.surface,
          child: strip,
        ),
      ),
    ),
  ),
);

Future<void> _capture(WidgetTester tester, String name) async {
  if (!const bool.fromEnvironment('PROFILE_TRADE_CAPTURE')) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(const Key('shot')));
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    const dir = '../.artifacts/trading-hall-intake-20261015/claude-direct-20261018/profile';
    await Directory(dir).create(recursive: true);
    await File('$dir/strip-$name.png').writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  setUpAll(loadFonts);
  for (final mode in [AppearanceMode.dark, AppearanceMode.light]) {
    testWidgets('owner sees the full strip with always-public marks (${mode.name})', (tester) async {
      tester.view.physicalSize = const Size(1100, 260);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var edits = 0;
      await tester.pumpWidget(_host(ProfileTradeStrip(data: _full, isSelf: true, onEdit: () => edits++), mode));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('profile-trade-always-public')), findsNWidgets(2));
      expect(find.text('Discord'), findsOneWidget);
      expect(find.text('现在可交易', findRichText: true), findsNothing);
      expect(find.textContaining('现在可交易'), findsOneWidget);
      await tester.tap(find.byKey(const Key('profile-trade-edit')));
      expect(edits, 1);
      await _capture(tester, 'self-${mode.name}');
    });
  }

  testWidgets('a visitor without access sees only the always-public fields', (tester) async {
    tester.view.physicalSize = const Size(1100, 260);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      _host(
        const ProfileTradeStrip(
          data: ProfileTradeStripData(
            localDays: [true, true, true, true, true, false, false],
            localWindow: '19:30–23:00',
            openNow: false,
            ownerWindow: '19:30–23:00 · UTC+08:00',
          ),
          isSelf: false,
        ),
        AppearanceMode.dark,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('profile-trade-always-public')), findsNothing);
    expect(find.byKey(const Key('profile-trade-edit')), findsNothing);
    expect(find.text('联系方式'), findsNothing);
    expect(find.text('SCM 信誉'), findsNothing);
    expect(find.textContaining('不在交易时段'), findsOneWidget);
    expect(find.textContaining('对方设置'), findsOneWidget);
    await _capture(tester, 'visitor-dark');
  });

  testWidgets('a missing profile becomes one prompt; narrow widths wrap without overflow', (tester) async {
    tester.view.physicalSize = const Size(480, 420);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      _host(ProfileTradeStrip(data: null, isSelf: true, onEdit: () {}), AppearanceMode.dark, width: 420),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('profile-trade-missing')), findsOneWidget);
    expect(find.text('设置交易资料'), findsOneWidget);
    await tester.pumpWidget(
      _host(ProfileTradeStrip(data: _full, isSelf: true, onEdit: () {}), AppearanceMode.light, width: 420),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await _capture(tester, 'narrow-light');
  });
}
