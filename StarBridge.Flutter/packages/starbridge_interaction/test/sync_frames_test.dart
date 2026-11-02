// Settings propagation frame convention (2026-10-10 recheck): an open
// dialog's content AND its scrim follow a settings change within two
// pumped frames (the change frame plus at most one more), whether the
// scope sits below or above the navigator.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import 'boundary_test.dart' show palette;

const _light = InteractionPalette(
  brightness: Brightness.light,
  accent: Color(0xFF1F7CC4),
  accentBright: Color(0xFF1F7CC4),
  onAccent: Color(0xFFFFFFFF),
  selectedFill: Color(0xFFDCEBF7),
  surface: Color(0xFFF4F7F9),
  raised: Color(0xFFFFFFFF),
  border: Color(0xFFB8C5CE),
  textPrimary: Color(0xFF14212A),
  textSecondary: Color(0xFF4A5B66),
  textDisabled: Color(0xFF9AA8B1),
  focusRing: Color(0xFF1F7CC4),
  success: Color(0xFF1E9E6A),
  onSuccess: Color(0xFFFFFFFF),
  danger: Color(0xFFD23F49),
  onDanger: Color(0xFFFFFFFF),
  warning: Color(0xFFB7791F),
);

const _darkScrim = Color(0xA6000000);
const _lightScrim = Color(0x66000000);

void main() {
  for (final midEntrance in [false, true]) {
    for (final above in [false, true]) {
      for (final suite in InteractionSuite.values) {
        testWidgets(
          '${suite.name}, scope ${above ? 'above' : 'below'} the navigator${midEntrance ? ', mid-entrance' : ''}: content and scrim within two frames',
          (t) async {
            final data = ValueNotifier(
              InteractionData(suite: suite, palette: palette),
            );
            addTearDown(data.dispose);
            InteractionData? seen;
            final opener = Builder(
              builder: (context) => GestureDetector(
                onTap: () => showSuiteDialog<void>(
                  context,
                  (ctx) => Builder(
                    builder: (ctx) {
                      seen = InteractionScope.of(ctx);
                      return const Text('dialog');
                    },
                  ),
                ),
                child: const Text('open'),
              ),
            );
            await t.pumpWidget(
              ValueListenableBuilder(
                valueListenable: data,
                builder: (context, d, _) => above
                    ? InteractionScope(
                        data: d,
                        child: MaterialApp(home: Scaffold(body: opener)),
                      )
                    : MaterialApp(
                        home: InteractionScope(
                          data: d,
                          child: Scaffold(body: opener),
                        ),
                      ),
              ),
            );
            await t.tap(find.text('open'));
            Color scrim() =>
                t.widget<ModalBarrier>(find.byType(ModalBarrier).last).color!;
            if (midEntrance) {
              await t.pump();
              await t.pump(const Duration(milliseconds: 60));
            } else {
              await t.pumpAndSettle();
              expect(scrim(), _darkScrim);
            }

            data.value = data.value.copyWith(
              palette: _light,
              reduceMotion: true,
            );
            await t.pump(); // the change frame
            await t.pump(); // at most one more
            expect(seen!.palette.isDark, isFalse, reason: 'content');
            expect(seen!.reduceMotion, isTrue, reason: 'content');
            expect(
              scrim(),
              _lightScrim,
              reason: 'scrim follows in the same window as the content',
            );
          },
        );
      }
    }
  }
}
