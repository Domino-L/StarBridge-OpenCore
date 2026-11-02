// Diagnostic coverage only: no production behavior changed.
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/account/account_module.dart';
import 'package:starbridge_flutter/features/account/in_memory_account_adapter.dart';
import 'package:starbridge_flutter/features/hangar/hangar_feature.dart';
import 'package:starbridge_flutter/features/hangar/local_hangar_port.dart';
import 'package:starbridge_flutter/app/shell/widgets/shell_workspace.dart';
import 'package:starbridge_flutter/app/shell/shell_navigation_controller.dart';
import 'hangar_reader_test.dart' as fixtures;

void main() {
  testWidgets('resize keeps inventory read count unchanged in workspace', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 720);
    addTearDown(tester.view.reset);
    final account = createAccountModule(InMemoryAccountAdapter.forReview(AccountReviewState.signedIn));
    await account.initialize();
    addTearDown(account.dispose);
    final port = _CountingPort();
    final feature = createHangarFeature(account, () => fixtures.PreviewFake(), localFactory: () => port);
    await tester.pumpWidget(fixtures.app(ShellWorkspace(selected: feature, interaction: NavigationInteraction.keyboard)));
    await tester.pumpAndSettle();
    expect(port.reads, 1);
    final scrollable = find.byType(CustomScrollView);
    for (var tick = 0; tick < 12; tick++) {
      await tester.sendEventToBinding(PointerScrollEvent(
        position: tester.getCenter(scrollable),
        scrollDelta: const Offset(0, 120),
        kind: PointerDeviceKind.mouse,
      ));
      await tester.pumpAndSettle();
      expect(find.textContaining('Diagnostic Ship').hitTestable(), findsWidgets);
      expect(port.reads, 1, reason: 'mouse wheel must not reload inventory');
      expect(tester.takeException(), isNull);
    }
    for (var cycle = 0; cycle < 4; cycle++) {
      await tester.drag(scrollable, const Offset(0, -1400));
      await tester.pumpAndSettle();
      expect(find.textContaining('Diagnostic Ship').hitTestable(), findsWidgets);
      expect(port.reads, 1);
      expect(tester.takeException(), isNull);
    }
    for (final width in [2560.0, 1280.0, 800.0, 1120.0, 1920.0, 800.0, 1280.0]) {
      tester.view.physicalSize = Size(width, 900);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(port.reads, 1, reason: 'resize to $width must not re-read inventory');
      expect(find.text('正在读取本机机库…'), findsNothing);
      expect(find.textContaining('Diagnostic Ship').hitTestable(), findsWidgets);
    }
    final position = tester.state<ScrollableState>(find.byType(Scrollable).last).position;
    position.jumpTo(0);
    await tester.pumpAndSettle();
    // Positive control: explicit refresh must reach the counted read boundary.
    await tester.tap(find.byKey(const Key('local-hangar-refresh')));
    await tester.pumpAndSettle();
    expect(port.reads, 2);
    await tester.pumpWidget(const SizedBox());
  });
}

class _CountingPort implements LocalHangarPort {
  int reads = 0;
  @override
  Future<LocalHangarSnapshot> read() async {
    reads++;
    return LocalHangarSnapshot(revision: 1, ships: List.generate(80, (i) => LocalHangarShip(id: 'diagnostic-$i', title: 'Diagnostic Ship $i')));
  }
  @override
  Future<LocalHangarSnapshot> save(String operationId, int expectedRevision, {bool confirmEmpty = false}) => throw UnimplementedError();
}
