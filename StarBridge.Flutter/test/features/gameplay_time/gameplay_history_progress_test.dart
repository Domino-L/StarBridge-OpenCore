import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/gameplay_time/gameplay_time_panel.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';

import 'gameplay_time_test.dart' as support;

class ScanHarness extends support.Harness {
  ScanHarness() {
    session.acceptHostCapabilities({
      ...session.hostCapabilities,
      'gameplayTime.historyProgress',
    });
  }
  bool complete = false, cancelled = false, malformed = false;
  @override
  void respond(BridgeEnvelope r) {
    if (!r.name.startsWith('gameplayTime.historyScan')) {
      super.respond(r);
      return;
    }
    if (r.name.endsWith('Cancel')) cancelled = true;
    final result = cancelled
        ? <String, Object?>{'schemaVersion': 1, 'state': 'cancelled'}
        : complete && r.name.endsWith('Read')
        ? <String, Object?>{
            'schemaVersion': 1,
            'state': 'preview',
            'previewId': 'synthetic-preview',
            'seconds': 5400,
            'sessions': 3,
            'incompleteSessions': 1,
            'skippedFiles': 2,
          }
        : <String, Object?>{
            'schemaVersion': 1,
            'state': 'scanning',
            'scanId': '11111111111111111111111111111111',
            'phase': 'scanning',
            'processedFiles': malformed ? 8 : 3,
            'totalFiles': 7,
            'readBytes': 1048576,
            'totalBytes': 2097152,
          };
    unawaited(
      pair.host.send(
        BridgeEnvelope(
          protocolVersion: 1,
          messageType: 'response',
          name: r.name,
          correlationId: r.correlationId,
          sessionGeneration: r.sessionGeneration,
          accountContext: r.accountContext,
          status: 'ok',
          payload: result,
        ),
      ),
    );
  }
}

Future<void> open(
  WidgetTester tester,
  ScanHarness h, {
  Locale locale = const Locale('zh', 'CN'),
}) async {
  await tester.pumpWidget(
    support.app(GameplayTimePanel(controller: h.controller), locale: locale),
  );
  await tester.pump();
  await tester.ensureVisible(find.byKey(const Key('gameplay-history-import')));
  await tester.tap(find.byKey(const Key('gameplay-history-import')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 250));
}

void main() {
  const screenshotDirectory = String.fromEnvironment(
    'HISTORY_PROGRESS_GOLDEN_DIR',
  );
  const traditionalFont = String.fromEnvironment('HISTORY_PROGRESS_TC_FONT');
  setUpAll(() async {
    if (screenshotDirectory.isEmpty) return;
    for (final font in {
      'Source Sans 3': 'assets/fonts/SourceSans3VF-Upright.ttf',
      'Saira': 'assets/fonts/Saira-VF.ttf',
      'Rajdhani': 'assets/fonts/Rajdhani-SemiBold.ttf',
      'Source Han Sans CN': 'assets/fonts/SourceHanSansCN-VF.ttf',
    }.entries) {
      await (FontLoader(font.key)..addFont(rootBundle.load(font.value))).load();
    }
    if (traditionalFont.isNotEmpty) {
      // Local render only: the Windows system font is not copied or distributed.
      await (FontLoader('Microsoft JhengHei UI')..addFont(
            File(traditionalFont).readAsBytes().then(ByteData.sublistView),
          ))
          .load();
    }
  });
  testWidgets(
    'actual scan progress stays usable beyond old timeout then previews without commit',
    (tester) async {
      final h = ScanHarness()..seconds = 600;
      await open(tester, h);
      expect(find.byKey(const Key('gameplay-history-scan')), findsOneWidget);
      expect(find.text('已处理 3 / 7 个日志文件'), findsOneWidget);
      expect(find.text('已读取 1.0 / 2.0 MiB'), findsOneWidget);
      await tester.pump(const Duration(seconds: 70));
      expect(h.controller.value.busy, isTrue);
      expect(h.controller.value.historyError, isNull);
      h.complete = true;
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('gameplay-history-scan')), findsNothing);
      expect(find.byKey(const Key('gameplay-history-preview')), findsOneWidget);
      expect(h.seconds, 600);
      expect(
        h.requests.where((r) => r.name == 'gameplayTime.historyConfirm'),
        isEmpty,
      );
      await tester.tap(find.byKey(const Key('gameplay-history-cancel')));
      await tester.pumpAndSettle();
      await h.close(tester);
    },
  );
  for (final method in ['button', 'escape']) {
    testWidgets('cancel scan by $method does not import or dismiss settings', (
      tester,
    ) async {
      final h = ScanHarness()..seconds = 600;
      await open(tester, h);
      if (method == 'button') {
        await tester.tap(find.byKey(const Key('gameplay-history-scan-cancel')));
      } else {
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      }
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pumpAndSettle();
      expect(h.cancelled, isTrue);
      expect(find.byType(GameplayTimePanel), findsOneWidget);
      expect(find.byKey(const Key('gameplay-history-scan')), findsNothing);
      expect(find.byKey(const Key('gameplay-history-preview')), findsNothing);
      expect(h.seconds, 600);
      expect(
        h.requests.where((r) => r.name == 'gameplayTime.historyConfirm'),
        isEmpty,
      );
      await h.close(tester);
    });
  }
  testWidgets('account switch retires scan dialog and ignores old result', (
    tester,
  ) async {
    final h = ScanHarness();
    await open(tester, h);
    h.changeAccount();
    h.complete = true;
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('gameplay-history-scan')), findsNothing);
    expect(h.controller.value.preview, isNull);
    expect(h.controller.value.seconds, 0);
    await h.close(tester);
  });
  testWidgets(
    'invalid aggregate progress fails without showing a fabricated percentage',
    (tester) async {
      final h = ScanHarness()..malformed = true;
      await open(tester, h);
      await tester.pumpAndSettle();
      expect(h.controller.value.historyError, 'unavailable');
      expect(h.controller.value.preview, isNull);
      expect(find.byKey(const Key('gameplay-history-scan')), findsNothing);
      await h.close(tester);
    },
  );
  for (final locale in [
    const Locale('zh', 'CN'),
    const Locale('zh', 'TW'),
    const Locale('en'),
  ]) {
    for (final width in [360.0, 1100.0]) {
      testWidgets('scan dialog fits $locale at $width', (tester) async {
        await tester.binding.setSurfaceSize(Size(width, 700));
        final h = ScanHarness();
        await open(tester, h, locale: locale);
        expect(find.byKey(const Key('gameplay-history-scan')), findsOneWidget);
        expect(tester.takeException(), isNull);
        if (screenshotDirectory.isNotEmpty) {
          await expectLater(
            find.byType(MaterialApp),
            matchesGoldenFile(
              Uri.directory(
                screenshotDirectory,
              ).resolve('scan-${locale.toLanguageTag()}-${width.toInt()}.png'),
            ),
          );
        }
        await h.controller.cancelHistoryScan();
        await tester.pump(const Duration(milliseconds: 250));
        await tester.pumpAndSettle();
        await h.close(tester);
        await tester.binding.setSurfaceSize(null);
      });
    }
  }
}
