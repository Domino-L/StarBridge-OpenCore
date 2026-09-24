import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/design_system/styles/future_restraint_style.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/communities/community_preset_dialog.dart';
import 'package:starbridge_flutter/features/communities/community_preset_port.dart';

import 'community_preset_test.dart';
import '../friends/social_layout_test.dart' show loadFonts;

Future<void> open(
  WidgetTester tester,
  PresetFake port, {
  bool importing = false,
  Locale locale = const Locale('zh', 'CN'),
  void Function(Object?)? onResult,
}) async {
  tester.view.physicalSize = const Size(460, 760);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      supportedLocales: AppStrings.supportedLocales,
      localizationsDelegates: const [
        AppStringsDelegate(),
        ...GlobalMaterialLocalizations.delegates,
      ],
      theme: buildStarBridgeTheme(
        FutureRestraintStyle.resolve(AppearanceMode.dark),
        locale,
      ),
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            child: const Text('Open'),
            onPressed: () async {
              final result = await showDialog<Object?>(
                context: context,
                barrierDismissible: false,
                builder: (_) => RepaintBoundary(
                  key: const ValueKey('preset-capture'),
                  child: CommunityPresetDialog(
                    port: port,
                    attachment: importing ? card : null,
                  ),
                ),
              );
              onResult?.call(result);
            },
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Open'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  setUpAll(loadFonts);
  late PresetFake port;
  setUp(() => port = PresetFake());
  tearDown(() => port.changes.close());
  testWidgets(
    'share selection returns attachment without importing or sending',
    (tester) async {
      Object? selected;
      await open(tester, port, onResult: (v) => selected = v);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Fixture'));
      await tester.pumpAndSettle();
      expect(selected, card);
      expect(port.exports, 1);
      expect(port.imports, 0);
      expect(port.revision, 9);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'import requires explicit action and cannot repeat after success',
    (tester) async {
      await open(tester, port, importing: true);
      await tester.pumpAndSettle();
      expect(port.imports, 0);
      await tester.tap(find.widgetWithText(FilledButton, '导入为新预设'));
      await tester.pumpAndSettle();
      expect(port.imports, 1);
      expect(find.text('已新增预设: Fixture'), findsOneWidget);
      expect(find.byType(FilledButton), findsNothing);
    },
  );
  testWidgets(
    'unknown import has no retry and explains checking local presets',
    (tester) async {
      port.failure = 'presetImportUnknown';
      await open(tester, port, importing: true);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '导入为新预设'));
      await tester.pumpAndSettle();
      expect(port.imports, 1);
      expect(find.text('重试'), findsNothing);
      expect(find.textContaining('避免重复导入'), findsOneWidget);
    },
  );
  testWidgets('revision conflict requires reread before another import', (
    tester,
  ) async {
    port.failure = 'presetChanged';
    await open(tester, port, importing: true);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '导入为新预设'));
    await tester.pumpAndSettle();
    expect(port.imports, 1);
    expect(find.byType(FilledButton), findsNothing);
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(port.reads, 2);
    expect(port.imports, 1);
  });
  testWidgets('invalidated dialog ignores late catalog and offers no import', (
    tester,
  ) async {
    port.heldRead = Completer();
    await open(tester, port, importing: true);
    port.changes.add(null);
    await tester.pump();
    port.heldRead!.complete(CommunityPresetCatalog.parse(catalogPayload()));
    await tester.pumpAndSettle();
    expect(find.byType(FilledButton), findsNothing);
    expect(port.imports, 0);
    expect(find.textContaining('账号状态'), findsOneWidget);
  });
  for (final locale in [const Locale('zh', 'TW'), const Locale('en')]) {
    testWidgets('import copy fits narrow $locale', (tester) async {
      await open(tester, port, importing: true, locale: locale);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('capture actual import confirmation', (tester) async {
    await open(tester, port, importing: true);
    await tester.pumpAndSettle();
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const ValueKey('preset-capture')),
    );
    await tester.runAsync(() async {
      final image = await boundary.toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await File('build/community-preset-dialog.png')
          .writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
    expect(tester.takeException(), isNull);
  });
}
