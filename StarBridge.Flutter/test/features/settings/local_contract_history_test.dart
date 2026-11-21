import 'package:flutter/widgets.dart' hide LocalHistoryEntry;
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/settings/local_event_history.dart';
import 'package:starbridge_flutter/features/settings/local_event_history_copy.dart';

void main() {
  test('contract category requests the existing history port', () async {
    final port = _Port();
    final controller = LocalHistoryController(port);
    addTearDown(controller.dispose);
    await controller.select('contract');
    expect(localEventCategories, contains('contract'));
    expect(port.category, 'contract');
    expect(controller.value.page!.entries.single.title, '合约完成：需要战术打击群');
    expect(controller.value.category, 'contract');
  });

  for (final (locale, label) in [
    (const Locale('zh', 'CN'), '合约'),
    (const Locale('zh', 'TW'), '合約'),
    (const Locale('en'), 'Contracts'),
  ]) {
    testWidgets('contract category label $locale', (tester) async {
      await tester.pumpWidget(
        Localizations(
          locale: locale,
          delegates: const [DefaultWidgetsLocalizations.delegate],
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: Builder(
              builder: (context) => Text(localHistoryText(context, 'contract')),
            ),
          ),
        ),
      );
      expect(find.text(label), findsOneWidget);
    });
  }
}

final class _Port implements LocalHistoryPort {
  String? category;
  @override
  Future<LocalHistoryPage> read({
    required String category,
    required int offset,
    required int pageSize,
    String? revision,
  }) async {
    this.category = category;
    return LocalHistoryPage(
      state: 'ready',
      totalCount: 1,
      filteredCount: 1,
      offset: offset,
      pageSize: pageSize,
      hasMore: false,
      revision: 'revision',
      entries: [
        LocalHistoryEntry(
          id: 'synthetic-contract-hash',
          at: DateTime.utc(2026, 10, 18, 6, 5),
          category: 'contract',
          eventType: 'ContractEnded',
          title: '合约完成：需要战术打击群',
          detail: '互安防务 - 战术打击群 · 接单到完成 2 小时 35 分',
        ),
      ],
    );
  }
}
