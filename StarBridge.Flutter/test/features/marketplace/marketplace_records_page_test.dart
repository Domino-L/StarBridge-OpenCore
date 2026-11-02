// 0.7.2 G5–G7 pages (approved preview trade-records-preview, 2026-10-21):
// reviews with summary, reports with SCM outcome, blocklist with a confirmed
// unblock. Renders go to OUT when given (review only, never committed).
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_interaction_theme.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_port.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_records_controller.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_records_page.dart';

import '../../design_system/interaction/interaction_batch3i_test.dart'
    show scopedApp;
import '../friends/social_layout_test.dart' show size;

class _Port implements MarketplaceRecordsPort {
  final calls = <(String, MarketRow)>[];
  final blocked = <String>{'r1', 'r2'};
  @override
  bool get recordsSupported => true;
  @override
  Future<MarketRow> records(
    String operation, [
    MarketRow input = const {},
  ]) async {
    calls.add((operation, input));
    final now = DateTime.now().millisecondsSinceEpoch;
    return switch (operation) {
      'reviews' => {
        'rows': [
          {
            'id': 1,
            'reviewer': 'A*****y',
            'rating': 5,
            'content': '发货很快，在新巴贝奇当场交接，沟通顺畅。',
            'transactionId': 'TX2026101900112',
            'auditStatus': 1,
            'createTime': now - 7200000,
          },
          {
            'id': 2,
            'reviewer': 'D*********8',
            'rating': 5,
            'content': '价格公道，推荐。',
            'transactionId': 'TX2026101800054',
            'auditStatus': 1,
            'createTime': now - 86400000,
          },
          {
            'id': 3,
            'reviewer': 'L****t',
            'rating': 4,
            'content': '护航任务按时到位，中途改线也配合。',
            'source': '合约',
            'auditStatus': 1,
            'createTime': now - 3 * 86400000,
          },
          {
            'id': 4,
            'reviewer': 'K***r',
            'rating': 4,
            'content': '',
            'transactionId': 'TX2026101500031',
            'auditStatus': 0,
            'createTime': now - 5 * 86400000,
          },
        ],
        'total': 4,
      },
      'reports' => {
        'rows': [
          {
            'id': 9,
            'transactionNumber': 'TX2026101700021',
            'reported': 'F*****e',
            'reportType': '未按约定交付',
            'content': '约好 20 点交接，对方一直不上线。',
            'status': '处理中',
            'createTime': now,
          },
          {
            'id': 8,
            'transactionNumber': 'TX2026100900008',
            'reported': 'R***m',
            'reportType': '欺诈',
            'content': '收款后拉黑了我。',
            'status': '已处理',
            'result': '已核实，对方账号封禁 30 天，交易已关闭。',
            'createTime': now,
            'handleTime': now,
          },
        ],
        'total': 2,
      },
      'blocklist' => {
        'rows': [
          for (final ref in blocked)
            {
              'ref': ref,
              'name': ref == 'r1' ? 'D*********8' : 'R***m',
              'reason': ref == 'r1' ? '多次爽约' : '疑似欺诈（已举报）',
              'createTime': now,
            },
        ],
        'total': blocked.length,
      },
      'unblock' => () {
        blocked.remove(input['ref']);
        return <String, Object?>{'ref': input['ref'], 'confirmed': true};
      }(),
      _ => throw StateError(operation),
    };
  }
}

Future<void> _fonts() async {
  for (final (family, file) in [
    ('Source Sans 3', 'assets/fonts/SourceSans3VF-Upright.ttf'),
    ('Saira', 'assets/fonts/Saira-VF.ttf'),
    ('Rajdhani', 'assets/fonts/Rajdhani-SemiBold.ttf'),
    ('Source Han Sans CN', 'assets/fonts/SourceHanSansCN-VF.ttf'),
    ('Source Code Pro', 'assets/fonts/SourceCodeVF-Upright.ttf'),
    (
      'MaterialIcons',
      '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts/materialicons-regular.otf',
    ),
  ]) {
    final bytes = File(file).readAsBytesSync();
    await (FontLoader(
      family,
    )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
  }
}

Future<void> _render(WidgetTester tester, String name) async {
  const out = String.fromEnvironment('OUT');
  if (out.isEmpty) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const Key('records-render')),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    File('$out/$name.png').writeAsBytesSync(png!.buffer.asUint8List());
  });
}

/// The whole app (dialogs included) on the hall's dark backdrop.
Widget _app(Widget child) => RepaintBoundary(
  key: const Key('records-render'),
  child: scopedApp(
    Scaffold(
      backgroundColor: const Color(0xFF0B1118),
      body: Padding(padding: const EdgeInsets.all(24), child: child),
    ),
    InteractionSuite.scan,
  ),
);

void main() {
  setUpAll(() async {
    if (const String.fromEnvironment('OUT').isNotEmpty) await _fonts();
  });

  testWidgets('reviews: summary over public reviews, pending marked', (
    tester,
  ) async {
    size(tester, const Size(1280, 720));
    final c = MarketplaceRecordsController(_Port());
    addTearDown(c.dispose);
    await tester.pumpWidget(_app(MarketplaceReviewsView(c)));
    await tester.pumpAndSettle();
    expect(
      find.text('4.7'),
      findsOneWidget,
      reason: '(5+5+4)/3, the pending one excluded',
    );
    expect(find.text('3 条已公开 · 1 条审核中'), findsOneWidget);
    expect(find.text('审核中'), findsOneWidget);
    expect(find.text('（只打了分，没有写评价）'), findsOneWidget);
    expect(find.text('合约'), findsOneWidget);
    await _render(tester, 'records-reviews');
  });

  testWidgets(
    'reports and blocklist; unblock asks once, cancel is the default',
    (tester) async {
      size(tester, const Size(1280, 720));
      final port = _Port();
      final c = MarketplaceRecordsController(port);
      addTearDown(c.dispose);
      await tester.pumpWidget(_app(MarketplaceReportsBlocksView(c)));
      await tester.pumpAndSettle();
      expect(find.text('处理结果：已核实，对方账号封禁 30 天，交易已关闭。'), findsOneWidget);
      expect(find.text('处理中'), findsOneWidget);
      await _render(tester, 'records-reports');

      await tester.tap(find.byKey(const ValueKey(('market-records-kind', 1))));
      await tester.pumpAndSettle();
      expect(find.text('原因：多次爽约'), findsOneWidget);
      await _render(tester, 'records-block');

      await tester.tap(find.byKey(const ValueKey(('market-unblock', 'r1'))));
      await tester.pumpAndSettle();
      expect(find.text('解除拉黑 D*********8？'), findsOneWidget);
      await _render(tester, 'records-unblock');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(
        port.calls.where((x) => x.$1 == 'unblock'),
        isEmpty,
        reason: 'Enter lands on 取消',
      );

      await tester.tap(find.byKey(const ValueKey(('market-unblock', 'r1'))));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('market-unblock-confirm')));
      await tester.pumpAndSettle();
      expect(port.calls.where((x) => x.$1 == 'unblock').single.$2, {
        'ref': 'r1',
      });
      expect(find.text('原因：多次爽约'), findsNothing, reason: 'list read again');
      expect(find.text('原因：疑似欺诈（已举报）'), findsOneWidget);
    },
  );
}
