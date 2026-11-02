import 'marketplace_port.dart';
import 'marketplace_records_controller.dart';

/// Reads one page into [list]; true when the read finished for the caller.
/// Shared by the contracts and warehouse controllers (records has its own).
Future<bool> loadHallPage(
  MarketRecordList list,
  Future<MarketRow> Function(int page) read, {
  bool more = false,
  required bool Function() live,
  required void Function() notify,
}) async {
  if (list.loading || more && !list.more) return false;
  list
    ..loading = true
    ..failed = false
    ..error = null;
  notify();
  try {
    final page = more ? list.page + 1 : 1;
    final data = await read(page);
    if (!live()) return false;
    final rows = hallRows(data);
    list
      ..rows = more ? [...list.rows, ...rows] : rows
      ..total = (data['total'] as num?)?.toInt() ?? rows.length
      ..page = page;
  } on MarketplaceTradeError catch (error) {
    if (!live()) return false;
    list
      ..failed = true
      ..error = error.code;
  } on Object {
    if (!live()) return false;
    list.failed = true;
  } finally {
    if (live()) {
      list.loading = false;
      notify();
    }
  }
  return true;
}

List<MarketRow> hallRows(MarketRow data) => [
  for (final row in data['rows'] as List? ?? const [])
    if (row is Map) row.cast<String, Object?>(),
];

void clearHallList(MarketRecordList list) => list
  ..rows = const []
  ..total = 0
  ..page = 0
  ..loading = false
  ..failed = false
  ..error = null;
