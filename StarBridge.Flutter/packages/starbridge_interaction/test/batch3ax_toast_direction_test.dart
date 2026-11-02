import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import 'boundary_test.dart' show palette;

class Host extends StatefulWidget {
  const Host(this.side, {super.key});
  final bool? side;
  @override
  State<Host> createState() => HostState();
}

class HostState extends State<Host> with SingleTickerProviderStateMixin {
  late final c = AnimationController(
    vsync: this,
    value: 0.2,
    duration: const Duration(milliseconds: 200),
  );
  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final child = const SizedBox(width: 200, height: 80);
    final surface = widget.side == null
        ? SuiteSurfaceTransition(
            animation: c,
            kind: SurfaceKind.toast,
            child: child,
          )
        : SuiteSurfaceTransition(
            animation: c,
            kind: SurfaceKind.toast,
            toastFromLeft: widget.side!,
            child: child,
          );
    return InteractionScope(
      data: const InteractionData(
        suite: InteractionSuite.rail,
        palette: palette,
      ),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Center(child: surface),
      ),
    );
  }
}

void main() {
  for (final side in [null, false, true]) {
    for (final exit in [false, true]) {
      testWidgets(
        'rail toast direction side=$side exit=$exit retains default',
        (t) async {
          final key = GlobalKey<HostState>();
          await t.pumpWidget(Host(side, key: key));
          final c = key.currentState!.c;
          if (exit) {
            c.value = 1;
            c.reverse();
            await t.pump();
            await t.pump(const Duration(milliseconds: 40));
          } else {
            c.forward();
            await t.pump();
          }
          final surface = t.widget<SuiteSurfaceTransition>(
            find.byType(SuiteSurfaceTransition),
          );
          expect(surface.toastFromLeft, side ?? false);
          final x = t
              .widget<Transform>(find.byType(Transform))
              .transform
              .getTranslation()
              .x;
          expect(x, side == true ? lessThan(0) : greaterThan(0));
          await t.pumpWidget(const SizedBox());
        },
      );
    }
  }
}
