// A hall card without a picture draws its category. The Host can run out of
// time on a cold page, so the rows it has no answer for are read again quietly.
import 'dart:async';
import 'dart:io';

// ignore: depend_on_referenced_packages
import 'package:fake_async/fake_async.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_category_recheck.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_controller.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_port.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_silhouette.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_widgets.dart';
import 'package:starbridge_flutter/features/onboarding/connection_mode_port.dart';
import 'package:starbridge_flutter/shared/remote_image.dart';
import 'package:starbridge_flutter/shared/remote_image_loader.dart';

import 'marketplace_slice4_test.dart' show preview;

MarketRead _page(List<MarketRow> rows) =>
    MarketRead({'rows': rows, 'total': rows.length}, DateTime(2026, 10, 30));

final class _Recheck {
  _Recheck(MarketRead first) {
    blocks['latest'] = first;
    recheck = MarketCategoryRecheck(
      current: (key) => blocks[key],
      store: (key, read) {
        blocks[key] = read;
        stores++;
      },
    );
  }
  final blocks = <String, MarketRead>{};
  late final MarketCategoryRecheck recheck;
  int stores = 0;
  int reads = 0;
  MarketRead? answer;
  void start() => recheck.track('latest', blocks['latest']!, () async {
    reads++;
    return answer ?? (throw const FormatException('Synthetic failure'));
  });
  List<MarketRow> get rows => blocks['latest']!.rows;
}

class _Port implements MarketplacePort {
  @override
  bool available = true;
  @override
  int generation = 1;
  int trendingReads = 0;
  bool answered = false;
  @override
  Future<MarketRead> read(
    String operation, {
    int id = 0,
    String keyword = '',
    int category = 0,
    int side = 1,
    int page = 1,
    String language = 'CN',
    Map<String, String> options = const {},
  }) async {
    if (operation != 'trending') return _page(const []);
    trendingReads++;
    return _page([
      answered
          ? {'id': 7, 'categoryId': 31}
          : {'id': 7, 'categoryPending': true},
    ]);
  }

  @override
  Future<MarketRow> preferences([MarketRow? value]) async => {'revision': 0};
  @override
  void dispose() {}
}

final class _Mode extends ChangeNotifier implements ConnectionModeControl {
  @override
  bool busy = false;
  @override
  bool failed = false;
  @override
  ConnectionModeSnapshot get snapshot => const ConnectionModeSnapshot();
  @override
  bool get allowsOnlineTraffic => true;
  @override
  bool get canEnterOffline => false;
  @override
  Future<bool> enterOffline() async => false;
}

/// A transfer that fails at once, or hangs until the client is closed.
final class _Client extends Fake implements HttpClient {
  _Client(this.hang);
  final bool Function() hang;
  final _open = <Completer<HttpClientRequest>>[];
  @override
  Duration? connectionTimeout;
  @override
  Future<HttpClientRequest> getUrl(Uri url) {
    if (!hang()) return Future.error(const SocketException('Synthetic failure'));
    final open = Completer<HttpClientRequest>();
    _open.add(open);
    return open.future;
  }

  @override
  void close({bool force = false}) {
    for (final open in _open) {
      if (!open.isCompleted) {
        open.completeError(const SocketException('Closed'));
      }
    }
    _open.clear();
  }
}

Widget _art(RemoteImageLoader loader, Widget child) => RemoteImageScope(
  loader: loader,
  child: preview(SizedBox.square(dimension: 64, child: child), AppearanceMode.dark),
);

void main() {
  test('rows the Host has no answer for are asked about, then settled', () {
    fakeAsync((clock) {
      final t = _Recheck(
        _page([
          {'orderNumber': 'a', 'categoryPending': true},
          {'orderNumber': 'b', 'categoryPending': true},
          {'orderNumber': 'c', 'categoryId': 3},
        ]),
      );
      t.answer = _page([
        {'orderNumber': 'a', 'categoryId': 41},
        {'orderNumber': 'b', 'categoryPending': true},
      ]);
      t.start();
      clock.elapse(const Duration(seconds: 3));
      expect(t.reads, 1);
      expect(t.rows[0]['categoryId'], 41);
      expect(t.rows[0].containsKey('categoryPending'), isFalse);
      expect(t.rows[1]['categoryPending'], isTrue);
      expect(t.rows[2]['categoryId'], 3);

      // An answer without a category: SCM files it nowhere, the generic icon.
      t.answer = _page([
        {'orderNumber': 'b'},
      ]);
      clock.elapse(const Duration(seconds: 10));
      expect(t.reads, 2);
      expect(t.rows[1].containsKey('categoryPending'), isFalse);
      expect(t.rows[1].containsKey('categoryId'), isFalse);
      clock.elapse(const Duration(minutes: 5));
      expect(t.reads, 2, reason: 'Nothing left to ask about');
    });
  });

  test('a page with nothing waiting never reads again', () {
    fakeAsync((clock) {
      final t = _Recheck(
        _page([
          {'orderNumber': 'a', 'categoryId': 3},
        ]),
      )..start();
      clock.elapse(const Duration(minutes: 5));
      expect(t.reads, 0);
    });
  });

  test('three rounds at most, failed reads included, then the row settles', () {
    fakeAsync((clock) {
      final t = _Recheck(
        _page([
          {'orderNumber': 'a', 'categoryPending': true},
        ]),
      )..start();
      clock.elapse(const Duration(seconds: 3));
      clock.elapse(const Duration(seconds: 10));
      expect(t.rows.single['categoryPending'], isTrue);
      clock.elapse(const Duration(seconds: 30));
      expect(t.reads, 3);
      expect(t.rows.single.containsKey('categoryPending'), isFalse);
      clock.elapse(const Duration(minutes: 5));
      expect(t.reads, 3);
    });
  });

  test('a newer read of the page or a cancel drops the old round', () {
    fakeAsync((clock) {
      final t = _Recheck(
        _page([
          {'orderNumber': 'a', 'categoryPending': true},
        ]),
      )..start();
      t.start();
      clock.elapse(const Duration(seconds: 3));
      expect(t.reads, 1, reason: 'One round, not two');
      t.recheck.cancel();
      clock.elapse(const Duration(minutes: 5));
      expect(t.reads, 1);
      expect(t.stores, 0);
    });
  });

  test('a read still running when cancelled cannot write into the next account', () {
    fakeAsync((clock) {
      final t = _Recheck(
        _page([
          {'orderNumber': 'a', 'categoryPending': true},
        ]),
      );
      final slow = Completer<MarketRead>();
      t.recheck.track('latest', t.blocks['latest']!, () => slow.future);
      clock.elapse(const Duration(seconds: 3));

      t.recheck.cancel();
      t.blocks['latest'] = _page([
        {'orderNumber': 'a', 'categoryPending': true},
      ]);
      t.answer = _page([
        {'orderNumber': 'a', 'categoryPending': true},
      ]);
      t.start();
      slow.complete(
        _page([
          {'orderNumber': 'a', 'categoryId': 99},
        ]),
      );
      clock.flushMicrotasks();
      expect(t.rows.single.containsKey('categoryId'), isFalse);
      expect(t.rows.single['categoryPending'], isTrue);
      t.recheck.cancel();
    });
  });

  testWidgets('a hall card waiting on its category fills in on its own', (
    tester,
  ) async {
    final port = _Port();
    final c = MarketplaceController(port);
    unawaited(c.initialize());
    for (var i = 0; i < 12; i++) {
      await tester.pump();
    }
    expect(c.blocks['trending']!.rows.single['categoryPending'], isTrue);
    final before = port.trendingReads;

    port.answered = true;
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
    expect(port.trendingReads, before + 1);
    expect(c.blocks['trending']!.rows.single['categoryId'], 31);
    expect(c.loading, isNot(contains('trending')), reason: 'A quiet read');
    c.dispose();
    await tester.pump(const Duration(minutes: 1));
  });

  testWidgets('an empty panel while a picture loads, its category if it fails', (
    tester,
  ) async {
    final mode = _Mode();
    var now = DateTime(2026, 10, 30);
    final loader = RemoteImageLoader(
      mode: mode,
      now: () => now,
      createClient: () => _Client(() => true),
    );
    await tester.pumpWidget(
      _art(
        loader,
        const MarketArt('https://example.invalid/item.png', category: 31),
      ),
    );
    await tester.pump();
    expect(find.byType(MarketSilhouette), findsNothing);

    // Its 10 seconds run out: failed, so the category shows.
    now = now.add(const Duration(seconds: 10));
    await tester.pump(const Duration(seconds: 10));
    await tester.pump();
    expect(
      tester.widget<MarketSilhouette>(find.byType(MarketSilhouette)).category,
      31,
    );

    // The reread hangs too; the icon stays up rather than blinking away.
    now = now.add(const Duration(seconds: 11));
    await tester.pump(const Duration(seconds: 11));
    await tester.pump();
    expect(find.byType(MarketSilhouette), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    loader.dispose();
    await tester.pump(const Duration(seconds: 11));
    mode.dispose();
  });

  testWidgets('a row waiting on its category stays empty, then shows it', (
    tester,
  ) async {
    await tester.pumpWidget(
      preview(
        SizedBox.square(
          dimension: 64,
          child: MarketArt.of(const {'id': 7, 'categoryPending': true}),
        ),
        AppearanceMode.dark,
      ),
    );
    await tester.pump();
    expect(find.byType(MarketSilhouette), findsNothing);

    await tester.pumpWidget(
      preview(
        SizedBox.square(
          dimension: 64,
          child: MarketArt.of(const {'id': 7, 'categoryId': 31}),
        ),
        AppearanceMode.dark,
      ),
    );
    await tester.pump();
    expect(
      tester.widget<MarketSilhouette>(find.byType(MarketSilhouette)).category,
      31,
    );
  });

  testWidgets('a row the Host answered without a category gets the generic icon', (
    tester,
  ) async {
    await tester.pumpWidget(
      preview(
        SizedBox.square(dimension: 64, child: MarketArt.of(const {'id': 7})),
        AppearanceMode.dark,
      ),
    );
    await tester.pump();
    expect(
      tester.widget<MarketSilhouette>(find.byType(MarketSilhouette)).category,
      0,
    );
  });
}
