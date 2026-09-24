import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/communities/communities_module.dart';

final class CursorPort implements CommunitiesPort {
  final afters = <String?>[];
  @override
  Stream<void> get invalidations => const Stream.empty();
  @override
  Future<CommunityDirectory> read({
    required String view,
    required String query,
    String? after,
    String? filters,
  }) async {
    afters.add(after);
    if (after != null) throw const CommunityFailure('refreshRequired');
    return CommunityDirectory(view, query, const [], next: 'expired-page');
  }

  @override
  Future<String> execute(String action, String targetRef) async => 'rejected';
  @override
  Future<void> close() async {}
}

void main() {
  test(
    'Retry after expired directory cursor restarts same search on first page',
    () async {
      final port = CursorPort();
      final model = CommunitiesModule(port);
      addTearDown(model.dispose);
      await model.refresh(
        newView: 'discover',
        newQuery: '探索',
        newFilters: '{}',
      );
      await model.next();
      expect(model.error, 'refreshRequired');
      await model.refresh();
      expect(port.afters, [null, 'expired-page', null]);
      expect(model.error, isNull);
      expect(model.query, '探索');
      expect(model.filters, '{}');
    },
  );
}
