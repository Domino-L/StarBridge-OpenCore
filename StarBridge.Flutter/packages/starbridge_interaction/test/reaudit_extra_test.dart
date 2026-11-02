// Recheck probes from the Codex audit (2026-10-06), kept as regression tests.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';
import 'boundary_test.dart' show palette;

void main() {
  testWidgets('route reduced motion settles its controller, not only its paint', (t) async {
    var reduce = false;
    late StateSetter change;
    late BuildContext launcher;
    late ModalRoute<void> dialogRoute;
    await t.pumpWidget(StatefulBuilder(builder: (context, set) {
      change = set;
      return InteractionScope(
        data: InteractionData(suite: InteractionSuite.scan, palette: palette, reduceMotion: reduce),
        child: MaterialApp(home: Scaffold(body: Builder(builder: (context) {
          launcher = context;
          return const SizedBox.shrink();
        }))));
    }));
    showSuiteDialog<void>(launcher, (context) {
      dialogRoute = ModalRoute.of<void>(context)!;
      return const Dialog(child: Text('dialog'));
    });
    await t.pump();
    await t.pump(const Duration(milliseconds: 40));
    expect(dialogRoute.animation!.status, AnimationStatus.forward);
    change(() => reduce = true);
    await t.pump();
    expect(find.text('dialog'), findsOneWidget);
    expect(dialogRoute.animation!.status, AnimationStatus.completed,
      reason: 'The route ticker must settle too; hiding visual motion alone is not stopping it.');
    expect(t.hasRunningAnimations, isFalse);
  });

  testWidgets('standard pressable keyboard activation has no new ink animation', (t) async {
    var calls = 0;
    InteractionSource? source;
    await t.pumpWidget(InteractionScope(
      data: const InteractionData(suite: InteractionSuite.standard, palette: palette),
      child: MaterialApp(home: Scaffold(body: SuitePressable(
        kind: PressableKind.secondary, onActivate: (v) { calls++; source = v; },
        child: const Text('go'))))));
    await t.pumpAndSettle();
    await t.sendKeyEvent(LogicalKeyboardKey.tab);
    await t.pumpAndSettle();
    expect(t.hasRunningAnimations, isFalse);
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pump();
    expect(calls, 1);
    expect(source, InteractionSource.keyboard);
    expect(t.hasRunningAnimations, isFalse,
      reason: 'Correct source reporting must not still create a keyboard Material ripple.');
  });
}
