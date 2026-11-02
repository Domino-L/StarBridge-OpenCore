import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/runtime/first_use_recovery_flow.dart';
import 'package:starbridge_flutter/features/onboarding/first_use_recovery_dialog.dart';
import 'package:starbridge_flutter/design_system/styles/future_restraint_style.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';

Future<BuildContext> page(
  WidgetTester tester, {
  Locale locale = const Locale('en', 'US'),
  double width = 800,
  double scale = 1,
}) async {
  tester.view.physicalSize = Size(width, 700);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  late BuildContext context;
  await tester.pumpWidget(
    MaterialApp(
      theme: buildStarBridgeTheme(
        FutureRestraintStyle.resolve(AppearanceMode.dark),
        locale,
      ),
      locale: locale,
      supportedLocales: const [
        Locale('en', 'US'),
        Locale('zh', 'CN'),
        Locale('zh', 'TW'),
      ],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: RepaintBoundary(
          key: const Key('recovery-capture'),
          child: child!,
        ),
      ),
      home: Builder(
        builder: (value) {
          context = value;
          return const Scaffold(body: Text('original page'));
        },
      ),
    ),
  );
  return context;
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    for (final font in <String, String>{
      'Source Sans 3': 'assets/fonts/SourceSans3VF-Upright.ttf',
      'Saira': 'assets/fonts/Saira-VF.ttf',
      'Rajdhani': 'assets/fonts/Rajdhani-SemiBold.ttf',
      'Source Han Sans CN': 'assets/fonts/SourceHanSansCN-VF.ttf',
    }.entries) {
      await (FontLoader(font.key)..addFont(rootBundle.load(font.value))).load();
    }
    if (Platform.isWindows) {
      await (FontLoader('Microsoft JhengHei UI')..addFont(
            File('C:/Windows/Fonts/msjh.ttc')
                .readAsBytes()
                .then((bytes) => ByteData.sublistView(bytes)),
          ))
          .load();
    }
  });
  for (final locale in [
    const Locale('zh', 'CN'),
    const Locale('zh', 'TW'),
    const Locale('en', 'US'),
  ]) {
    testWidgets('recovery choices fit real fonts at 320/160% in $locale', (
      tester,
    ) async {
      final context = await page(
        tester,
        locale: locale,
        width: 320,
        scale: 1.6,
      );
      final notice = FirstUseRecoveryNotice(
        'unreadableProgress',
        () => true,
        () async => 'unreadableProgress',
      );
      final result = showFirstUseRecovery(context, notice);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      for (final key in ['keep', 'recheck', 'open']) {
        expect(find.byKey(Key('first-use-recovery-$key')), findsOneWidget);
      }
      final captureDirectory =
          Platform.environment['STARBRIDGE_RECOVERY_CAPTURE_DIR'];
      if (captureDirectory != null) {
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const Key('recovery-capture')),
        );
        await tester.runAsync(() async {
          final image = await boundary.toImage();
          try {
            final bytes = (await image.toByteData(
              format: ui.ImageByteFormat.png,
            ))!;
            await File('$captureDirectory/recovery-$locale.png').writeAsBytes(
              bytes.buffer.asUint8List(
                bytes.offsetInBytes,
                bytes.lengthInBytes,
              ),
            );
          } finally {
            image.dispose();
          }
        });
      }
      await tester.tap(find.byKey(const Key('first-use-recovery-keep')));
      await tester.pumpAndSettle();
      expect(await result, FirstUseRecoveryChoice.keepCurrent);
      notice.dispose();
    });
  }
  for (final selection in ['keep', 'open']) {
    testWidgets('$selection is navigation only and does not run a recheck', (
      tester,
    ) async {
      final context = await page(tester);
      var reads = 0;
      final notice = FirstUseRecoveryNotice(
        'installationUnknown',
        () => true,
        () async {
          reads++;
          return 'unavailable';
        },
      );
      final result = showFirstUseRecovery(context, notice);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(Key('first-use-recovery-$selection')));
      await tester.pumpAndSettle();
      expect(
        await result,
        selection == 'keep'
            ? FirstUseRecoveryChoice.keepCurrent
            : FirstUseRecoveryChoice.openSetup,
      );
      expect(reads, 0);
      notice.dispose();
    });
  }
  testWidgets(
    'recheck retains records guidance and disables all choices until its original read finishes',
    (tester) async {
      final context = await page(tester), held = Completer<String?>();
      var reads = 0;
      final notice = FirstUseRecoveryNotice('unavailable', () => true, () {
        reads++;
        return held.future;
      });
      final result = showFirstUseRecovery(context, notice);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('first-use-recovery-recheck')));
      await tester.pump();
      expect(
        tester
            .widget<TextButton>(
              find.byKey(const Key('first-use-recovery-keep')),
            )
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<OutlinedButton>(
              find.byKey(const Key('first-use-recovery-recheck')),
            )
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const Key('first-use-recovery-open')),
            )
            .onPressed,
        isNull,
      );
      expect(reads, 1);
      held.complete('switching');
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        find.textContaining(
          'The mode change is still running. Check again later.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('first-use-recovery-keep')));
      await tester.pumpAndSettle();
      await result;
      notice.dispose();
    },
  );
  testWidgets(
    'successful recheck closes only this prompt and does not open setup or claim completion',
    (tester) async {
      final context = await page(tester);
      var reads = 0;
      final notice = FirstUseRecoveryNotice(
        'unreadableHistory',
        () => true,
        () async {
          reads++;
          return 'ready';
        },
      );
      final result = showFirstUseRecovery(context, notice);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('first-use-recovery-recheck')));
      await tester.pumpAndSettle();
      expect(await result, FirstUseRecoveryChoice.keepCurrent);
      expect(reads, 1);
      expect(tester.takeException(), isNull);
      expect(find.text('original page'), findsOneWidget);
      notice.dispose();
    },
  );
  testWidgets(
    'retiring an old notice removes only its own route and preserves a manual draft route',
    (tester) async {
      final context = await page(tester);
      final notice = FirstUseRecoveryNotice(
        'pending',
        () => true,
        () async => 'pending',
      );
      final result = showFirstUseRecovery(context, notice);
      await tester.pumpAndSettle();
      final draft = Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => const Scaffold(body: Text('unsaved manual draft')),
        ),
      );
      await tester.pumpAndSettle();
      notice.retire();
      await tester.pumpAndSettle();
      expect(await result, isNull);
      expect(find.text('unsaved manual draft'), findsOneWidget);
      expect(tester.takeException(), isNull);
      Navigator.of(context).pop();
      await tester.pumpAndSettle();
      await draft;
      notice.dispose();
    },
  );
  testWidgets('retired notice cannot act on a late successful recheck', (
    tester,
  ) async {
    final context = await page(tester), held = Completer<String?>();
    final notice = FirstUseRecoveryNotice(
      'pending',
      () => true,
      () => held.future,
    );
    final result = showFirstUseRecovery(context, notice);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('first-use-recovery-recheck')));
    await tester.pump();
    notice.retire();
    await tester.pumpAndSettle();
    expect(await result, isNull);
    held.complete('ready');
    await tester.pump();
    expect(tester.takeException(), isNull);
    notice.dispose();
  });
}
