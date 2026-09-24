import '../../platform/bridge/bridge_client_session.dart';
import 'local_event_history.dart';

final class BridgeLocalEventHistory implements LocalHistoryPort {
  BridgeLocalEventHistory(this.session);
  final BridgeClientSession session;
  @override
  Future<LocalHistoryPage> read({
    required String category,
    required int offset,
    required int pageSize,
    String? revision,
  }) async {
    try {
      final p = (await session.request(
        'diagnostics.getLocalEvents',
        payload: {
          'schemaVersion': 1,
          'category': category,
          'offset': offset,
          'pageSize': pageSize,
          'revision': revision,
        },
      )).payload;
      final total = p['totalCount'],
          count = p['filteredCount'],
          rows = p['entries'],
          rev = p['revision'];
      if (p.length != 9 ||
          p['schemaVersion'] != 1 ||
          !p.containsKey('revision') ||
          !const {
            'ready',
            'missing',
            'recovered',
            'unavailable',
          }.contains(p['state']) ||
          total is! int ||
          total < 0 ||
          total > 3000 ||
          count is! int ||
          count < 0 ||
          count > total ||
          p['offset'] != offset ||
          p['pageSize'] != pageSize ||
          p['hasMore'] is! bool ||
          rev != null &&
              (rev is! String || !RegExp(r'^[0-9A-F]{64}$').hasMatch(rev)) ||
          rows is! List ||
          rows.length > pageSize) {
        throw const FormatException('Invalid event history page.');
      }
      final entries = rows
          .map((raw) {
            if (raw is! Map ||
                raw.length != 6 ||
                !_text(raw['id'], 128) ||
                !_text(raw['title'], 180) ||
                !_text(raw['detail'], 500, empty: true) ||
                !_text(raw['eventType'], 80) ||
                !localEventCategories.skip(1).contains(raw['category']) ||
                raw['occurredAt'] is! String) {
              throw const FormatException('Invalid event history entry.');
            }
            final date = DateTime.tryParse(raw['occurredAt'] as String);
            if (date == null ||
                !RegExp(r'(?:Z|[+-]\d\d:\d\d)$')
                    .hasMatch(raw['occurredAt'] as String)) {
              throw const FormatException('Invalid event time.');
            }
            return LocalHistoryEntry(
              id: raw['id'] as String,
              at: date,
              category: raw['category'] as String,
              eventType: raw['eventType'] as String,
              title: raw['title'] as String,
              detail: raw['detail'] as String,
            );
          })
          .toList(growable: false);
      final unavailable =
          p['state'] == 'missing' || p['state'] == 'unavailable';
      if (entries.length != (count - offset).clamp(0, pageSize) ||
          p['hasMore'] != (offset + entries.length < count) ||
          entries.map((e) => e.id).toSet().length != entries.length ||
          category != 'all' && entries.any((e) => e.category != category) ||
          unavailable && (total != 0 || entries.isNotEmpty || rev != null) ||
          !unavailable && rev == null ||
          revision != null && revision != rev) {
        throw const FormatException('Inconsistent event history page.');
      }
      return LocalHistoryPage(
        state: p['state'] as String,
        totalCount: total,
        filteredCount: count,
        offset: offset,
        pageSize: pageSize,
        hasMore: p['hasMore'] as bool,
        entries: entries,
        revision: rev as String?,
      );
    } on BridgeClientException catch (error) {
      throw LocalHistoryException(
        error.code == 'localEvents.historyChanged' ? 'changed' : 'unavailable',
      );
    }
  }

  static bool _text(Object? value, int limit, {bool empty = false}) =>
      value is String &&
      value.length <= limit &&
      (empty || value.trim().isNotEmpty) &&
      !RegExp(r'[\x00-\x1f\x7f]').hasMatch(value);
}
