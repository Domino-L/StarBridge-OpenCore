import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_dialog.dart';
import 'package:starbridge_flutter/features/communities/community_ship_detail_dialog.dart';
import 'package:starbridge_flutter/features/communities/community_image_decoder.dart';
import 'package:starbridge_flutter/features/communities/community_ship_image_port.dart';
import 'package:starbridge_flutter/features/communities/community_ship_report_dialog.dart';
import 'package:starbridge_flutter/features/communities/community_ship_report_port.dart';
import 'package:starbridge_flutter/features/communities/community_ships_port.dart';
import 'package:starbridge_flutter/features/communities/community_workspace_image.dart';

import '../official_fleet/official_fleet_hangar_sharing_test.dart' show host;
import '../official_fleet/official_fleet_image_test_support.dart';
import '../friends/social_layout_test.dart' show loadFonts;

class _Port
    implements
        CommunityShipsPort,
        CommunityShipImagePort,
        CommunityShipReportPort,
        CommunityShipReportReceiptScope {
  final changes = StreamController<void>.broadcast();
  final retirements = StreamController<void>.broadcast();
  int reads = 0, images = 0, posts = 0, checks = 0;
  bool receiptAvailable = true;
  String checkStatus = 'accepted';
  @override
  Stream<void> get invalidations => changes.stream;
  @override
  Stream<void> get reportReceiptRetirements => retirements.stream;
  @override
  bool get reportReceiptQueryAvailable => receiptAvailable;
  @override
  bool get shipsAvailable => true;
  @override
  bool get shipImageAvailable => true;
  @override
  bool get shipReportAvailable => true;
  CommunityShipsPage page([CommunityShipQuery? query]) =>
      CommunityShipsPage.parse(
        imagePage({
          'sourceRef': source,
          'targetRef': ref(9),
          'offset': 0,
          'query': (query ?? CommunityShipQuery()).toPayload(),
        }),
        officialImages: true,
      );
  @override
  Future<CommunityShipsPage> readShips(
    String targetRef, {
    int offset = 0,
    String? revision,
    CommunityShipQuery? query,
  }) async {
    reads++;
    return page(query);
  }

  @override
  Future<Map<String, Object?>> readShipImage(
    String targetRef,
    String shipRef, {
    required int offset,
    String? version,
  }) async {
    images++;
    return imageChunk({'targetRef': targetRef, 'shipRef': shipRef});
  }

  @override
  Future<CommunityShipReportOutcome> reportShipImage(
    CommunityShipReportIntent intent,
  ) async {
    posts++;
    return const CommunityShipReportOutcome('unknown', error: 'outcomeUnknown');
  }

  @override
  Future<CommunityShipReportOutcome> checkShipReport(
    CommunityShipReportIntent intent,
  ) async {
    checks++;
    return CommunityShipReportOutcome(
      checkStatus,
      error: checkStatus == 'unknown' ? 'outcomeUnknown' : null,
    );
  }

  Future<void> close() async {
    await changes.close();
    await retirements.close();
  }
}

Future<void> _open(WidgetTester tester, _Port port) async {
  // Engine codec completion is outside WidgetTest FakeAsync. Decode the real
  // synthetic PNG once there; each widget still owns a separate image handle.
  final decoded = (await tester.runAsync(
    () => decodeCommunityImage(pngBytes, 1024),
  ))!;
  addTearDown(decoded.dispose);
  tester.view.physicalSize = const Size(1280, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    host(
      Builder(
        builder: (context) => TextButton(
          onPressed: () => showStarBridgeDialog<void>(
            context,
            builder: (_) => CommunityShipDetailDialog(
              port: port,
              page: port.page(),
              shipRef: ref(1),
              imageDecoder: (_, _) async => decoded.clone(),
              ownerTargetFactory: null,
            ),
          ),
          child: const Text('Open detail'),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Open detail'));
  await tester.pumpAndSettle();
  expect(port.images, 1);
  expect(find.byKey(const Key('community-ship-custom-image')), findsOneWidget);
  await tester.tap(find.byKey(const Key('community-ship-report-image')));
  await tester.pumpAndSettle();
  expect(find.byType(CommunityShipReportDialog), findsOneWidget);
}

Future<void> _submit(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('ship-report-reason-control')));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Inappropriate content').last);
  await tester.pumpAndSettle();
  await tester.enterText(
    find.byKey(const Key('ship-report-details')),
    'My report details',
  );
  await tester.tap(find.byKey(const Key('ship-report-submit')));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(loadFonts);
  testWidgets(
    'unknown dispatched dialog survives source loss while remote content is removed',
    (tester) async {
      final port = _Port();
      addTearDown(port.close);
      await _open(tester, port);
      await _submit(tester);
      expect(port.posts, 1);
      port.changes.add(null);
      await tester.pumpAndSettle();
      expect(find.byType(CommunityShipDetailDialog), findsNothing);
      expect(find.byType(CommunityShipReportDialog), findsOneWidget);
      expect(find.byType(CommunityWorkspaceImage), findsNothing);
      expect(find.text('Arrow'), findsNothing);
      expect(find.text('Bridge Pilot'), findsNothing);
      expect(
        find.byKey(const Key('ship-report-source-retired')),
        findsOneWidget,
      );
      expect(find.text('My report details'), findsOneWidget);
      await tester.tap(find.byKey(const Key('ship-report-submit')));
      await tester.pumpAndSettle();
      expect(port.checks, 1);
      expect(port.posts, 1);
      expect(find.text('Report submitted for review.'), findsOneWidget);
      expect(port.images, 1);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('unknown status preserves query action and never posts again', (
    tester,
  ) async {
    final port = _Port()..checkStatus = 'unknown';
    addTearDown(port.close);
    await _open(tester, port);
    await _submit(tester);
    port.changes.add(null);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('ship-report-submit')));
    await tester.pumpAndSettle();
    expect(port.posts, 1);
    expect(port.checks, 1);
    expect(find.text('Check result'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(CommunityShipReportDialog), findsOneWidget);
    expect(find.text('Keep checking'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'unsent source-scoped draft closes instead of becoming a receipt',
    (tester) async {
      final port = _Port();
      addTearDown(port.close);
      await _open(tester, port);
      await tester.enterText(
        find.byKey(const Key('ship-report-details')),
        'Unsent',
      );
      port.changes.add(null);
      await tester.pumpAndSettle();
      expect(find.byType(CommunityShipReportDialog), findsNothing);
      expect(find.byType(CommunityShipDetailDialog), findsNothing);
      expect(port.posts, 0);
      expect(port.checks, 0);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('receipt-owner retirement closes and clears dispatched report', (
    tester,
  ) async {
    final port = _Port();
    addTearDown(port.close);
    await _open(tester, port);
    await _submit(tester);
    port.retirements.add(null);
    port.changes.add(null);
    await tester.pumpAndSettle();
    expect(find.byType(CommunityShipReportDialog), findsNothing);
    expect(find.text('My report details'), findsNothing);
    expect(port.posts, 1);
    expect(port.checks, 0);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'temporarily unavailable status is explicit and never submits again',
    (tester) async {
      final port = _Port();
      addTearDown(port.close);
      await _open(tester, port);
      await _submit(tester);
      port.receiptAvailable = false;
      port.changes.add(null);
      await tester.pumpAndSettle();
      final submit = tester.widget<FilledButton>(
        find.byKey(const Key('ship-report-submit')),
      );
      expect(submit.onPressed, isNull);
      expect(
        find.text(
          'The result is unavailable right now. Check again when connected; do not submit again.',
        ),
        findsOneWidget,
      );
      expect(port.checks, 0);
      expect(port.posts, 1);
      port.receiptAvailable = true;
      port.changes.add(null);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('ship-report-submit')));
      await tester.pumpAndSettle();
      expect(port.checks, 1);
      expect(port.posts, 1);
      expect(tester.takeException(), isNull);
    },
  );
}
