// A trade dialog outlives its opener: the page behind may leave the tree
// while the dialog is open (main-tree full run, build 21). Rebuilding the
// dialog then must not look up through the departed opener.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_interaction_theme.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_trade_feedback.dart';

class _Host extends StatefulWidget {
  const _Host();
  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  bool opener = true;
  int tick = 0;
  void change({bool leave = false}) => setState(() {
    if (leave) opener = false;
    tick++;
  });
  @override
  Widget build(BuildContext context) => MaterialApp(
    // A new theme each tick rebuilds every route, the dialog included.
    theme: ThemeData(visualDensity: VisualDensity(horizontal: tick * 0.0)),
    builder: (context, child) => StarBridgeInteractionConfiguration(
      suite: InteractionSuite.scan,
      child: child!,
    ),
    home: Scaffold(
      body: opener
          ? Builder(
              builder: (context) => TextButton(
                onPressed: () => tradeMotionDialog<void>(
                  context,
                  (_) => const AlertDialog(content: Text('dialog')),
                ),
                child: const Text('open'),
              ),
            )
          : const Text('elsewhere'),
    ),
  );
}

void main() {
  testWidgets('the dialog rebuilds after its opener left the tree', (
    tester,
  ) async {
    await tester.pumpWidget(const _Host());
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('dialog'), findsOneWidget);
    final host = tester.state<_HostState>(find.byType(_Host));
    host.change(leave: true);
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('dialog'), findsOneWidget);
    host.change();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
