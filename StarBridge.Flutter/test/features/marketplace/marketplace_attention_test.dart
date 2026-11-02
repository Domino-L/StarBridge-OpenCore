// 0.7.2 sidebar 交易大厅 count (approved option A + C): trades waiting on me
// plus unread trade messages; the breakdown card on hover and focus.
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/feature_registry.dart';
import 'package:starbridge_flutter/app/shell/shell_layout_mode.dart';
import 'package:starbridge_flutter/app/shell/widgets/navigation_item.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_interaction_theme.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_attention.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_chat_controller.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_controller.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_port.dart';

import '../../design_system/interaction/interaction_batch3i_test.dart'
    show scopedApp;
import '../friends/social_layout_test.dart' show size;
import 'marketplace_trades_test.dart' show TradesPort;

MarketRow _trade(
  String n,
  String role,
  int delivery, {
  int status = 1,
  int creator = 1,
}) => {
  'transactionNumber': n,
  'actorRole': role,
  'creatorType': creator,
  'deliveryStatus': delivery,
  'transactionStatus': status,
  'number': 1,
};

class _Chat implements MarketplaceChatPort {
  final pushes = StreamController<MarketRow>.broadcast(sync: true);
  @override
  bool get chatSupported => true;
  @override
  Stream<MarketRow> get chatPushes => pushes.stream;
  @override
  Future<MarketRow> chat(
    String operation, [
    MarketRow input = const {},
  ]) async => operation == 'unread' ? {'count': 2} : {'rows': <MarketRow>[]};
}

Future<(MarketplaceAttention, MarketplaceController, _Chat)>
_attention() async {
  final port = TradesPort()
    ..pages[1] = [
      _trade('A', 'buyer', 0, creator: 0), // to approve
      _trade('S', 'seller', 1), // to ship
      _trade('R', 'buyer', 2), // to receive
      _trade('V', 'seller', 3, status: 2), // to review
      _trade('W', 'buyer', 1), // waiting on the seller
    ];
  final market = MarketplaceController(port);
  final chat = _Chat();
  final a = MarketplaceAttention(market, MarketplaceChatController(chat));
  a.follow(signedIn: true);
  unawaited(a.prefetch());
  return (a, market, chat);
}

void main() {
  setUpAll(() async {
    if (const String.fromEnvironment('OUT').isEmpty) return;
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
  });

  test('counts what waits on me plus unread trade messages', () async {
    final (a, market, chat) = await _attention();
    addTearDown(a.dispose);
    await pumpEventQueue();
    expect(
      (a.approve, a.ship, a.receive, a.review, a.messages),
      (1, 1, 1, 1, 2),
    );
    expect(a.value, 6);
    chat.pushes.add({'kind': 'unread', 'count': 5});
    expect(a.value, 9, reason: 'a live push updates the badge at once');
    a.follow(signedIn: false);
    expect(a.messages, 0);
    final reads = (market.port as TradesPort).reads;
    await a.prefetch();
    expect(
      (market.port as TradesPort).reads,
      reads,
      reason: 'nothing is read while signed out',
    );
  });

  testWidgets('hover and focus show the breakdown; the card opens 我的交易', (
    tester,
  ) async {
    size(tester, const Size(700, 420));
    late MarketplaceAttention a;
    late MarketplaceController market;
    await tester.runAsync(() async {
      (a, market, _) = await _attention();
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    addTearDown(a.dispose);
    var opened = 0;
    final feature = FeatureDescriptor(
      id: 'marketplace',
      route: '/marketplace',
      labelKey: 'navigation.marketplace',
      descriptionKey: 'navigation.marketplace.description',
      icon: StarBridgeIconSemantic.marketplace,
      navigationRegion: NavigationRegion.primary,
      order: 40,
      buildDestination: (_) => const SizedBox(),
      attentionCount: a,
      attentionDetail: a.detail(),
    );
    await tester.pumpWidget(
      RepaintBoundary(
        key: const Key('attention-render'),
        child: scopedApp(
          Scaffold(
            backgroundColor: const Color(0xFF0B1118),
            body: Align(
              alignment: Alignment.topLeft,
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: SizedBox(
                  width: 220,
                  child: ShellNavigationItem(
                    descriptor: feature,
                    mode: ShellLayoutMode.wide,
                    selected: false,
                    onPressed: () => opened++,
                    onKeyboardPressed: () {},
                    onPrevious: () {},
                    onNext: () {},
                  ),
                ),
              ),
            ),
          ),
          InteractionSuite.scan,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('6'),
      findsOneWidget,
      reason: 'option A: the plain red count',
    );
    expect(find.byKey(const Key('attention-detail-card')), findsNothing);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(find.byType(ShellNavigationItem)));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const Key('attention-detail-card')), findsOneWidget);
    expect(find.text('待你发货'), findsOneWidget);
    expect(find.text('交易私信未读'), findsOneWidget);
    await _render(tester);

    // The pointer can travel onto the card and use it.
    await mouse.moveTo(
      tester.getCenter(find.byKey(const Key('market-attention-open'))),
    );
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const Key('attention-detail-card')), findsOneWidget);
    await tester.tap(find.byKey(const Key('market-attention-open')));
    await tester.pump();
    expect(opened, 1);
    expect(market.mainTab, 3);

    await mouse.moveTo(const Offset(690, 410));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const Key('attention-detail-card')), findsNothing);

    // Keyboard focus shows it too, and the reader gets the full breakdown.
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byKey(const Key('attention-detail-card')), findsOneWidget);
    expect(
      find.bySemanticsLabel(RegExp('待你同意 1，待你发货 1，待你收货 1，待你评价 1，交易私信未读 2')),
      findsOneWidget,
    );
  });
}

Future<void> _render(WidgetTester tester) async {
  const out = String.fromEnvironment('OUT');
  if (out.isEmpty) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const Key('attention-render')),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    File('$out/badge-hover.png').writeAsBytesSync(png!.buffer.asUint8List());
  });
}
