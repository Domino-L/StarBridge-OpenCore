// The shared time-of-day lists (user decision 2026-10-22: picked, never
// typed; hour and minute apart; one component everywhere).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_interaction_theme.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_select_form_field.dart';
import 'package:starbridge_flutter/shared/clock_field.dart';

import '../design_system/interaction/interaction_batch3i_test.dart'
    show scopedApp;

/// Opens one list of a clock field and picks [value] (hour 0–23 or minute).
Future<void> pickClock(
  WidgetTester tester,
  String keyPrefix,
  String part,
  int value,
) async {
  final control = find.byKey(ValueKey('$keyPrefix-$part-control'));
  await tester.ensureVisible(control);
  await tester.tap(control);
  await tester.pumpAndSettle();
  final row = find.byKey(ValueKey<Object>(('$keyPrefix-$part', value)));
  await tester.ensureVisible(row);
  await tester.tap(row);
  await tester.pumpAndSettle();
}

/// The `HH:mm` a clock field shows, or null while it shows the 时 / 分 hints.
String? clockShown(WidgetTester tester, String keyPrefix) {
  int? read(String part) => tester
      .widget<StarBridgeSelectFormField<int>>(
        find.byKey(ValueKey('$keyPrefix-$part')),
      )
      .initialValue;
  final h = read('hour'), m = read('minute');
  return h == null || m == null ? null : clockText(h * 60 + m);
}

class _Range extends StatefulWidget {
  const _Range(this.start, this.end, {this.min = 60, super.key});
  final String start, end;
  final int min;
  @override
  State<_Range> createState() => _RangeState();
}

class _RangeState extends State<_Range> {
  late String start = widget.start, end = widget.end;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 520,
    child: StarBridgeTimeRangeField(
      keyPrefix: 'range',
      start: start,
      end: end,
      startLabel: 'Start',
      endLabel: 'End',
      minMinutes: widget.min,
      allowFullDay: false,
      onChanged: (s, e) => setState(() {
        start = s;
        end = e;
      }),
    ),
  );
}

void main() {
  test('reads and writes only HH:mm', () {
    expect(clockMinutes('23:30'), 1410);
    for (final bad in ['24:00', '7:00', '1212121212121212:00', '', null]) {
      expect(clockMinutes(bad), -1, reason: '$bad');
    }
    expect(clockText(65), '01:05');
    expect(StarBridgeTimeRangeField.length('23:30', '01:00'), 90);
    expect(StarBridgeTimeRangeField.length('10:00', '10:00'), 1440);
    expect(
      StarBridgeTimeRangeField.length('10:00', '10:00', allowFullDay: false),
      0,
    );
  });

  testWidgets('range end marks next day, greys out short ends, keeps odd '
      'minutes', (tester) async {
    await tester.pumpWidget(
      scopedApp(
        const Material(child: _Range('23:30', '01:00')),
        InteractionSuite.scan,
      ),
    );
    await tester.pumpAndSettle();
    expect(clockShown(tester, 'range-end'), '01:00');
    expect(find.byKey(const ValueKey('range-summary')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('range-end-hour-control')));
    await tester.pumpAndSettle();
    final menu = tester.widget<StarBridgeSelectFormField<int>>(
      find.byKey(const ValueKey('range-end-hour')),
    );
    final items = {for (final i in menu.items!) i.value: i};
    expect(items[0]!.enabled, isTrue, reason: '00:30–00:45 still fit');
    expect(items[1]!.enabled, isTrue);
    await tester.tapAt(Offset.zero);
    await tester.pumpAndSettle();

    // From 00 the minute moves to the first one that keeps an hour.
    await pickClock(tester, 'range-end', 'hour', 0);
    expect(clockShown(tester, 'range-end'), '00:30');

    // A minute off the quarter grid stays listed as the current value.
    await tester.pumpWidget(
      scopedApp(
        const Material(
          child: _Range('19:10', '22:00', min: 1, key: ValueKey('odd')),
        ),
        InteractionSuite.scan,
      ),
    );
    await tester.pumpAndSettle();
    final minutes = tester.widget<StarBridgeSelectFormField<int>>(
      find.byKey(const ValueKey('range-start-minute')),
    );
    expect(minutes.items!.map((i) => i.value), [10, 0, 15, 30, 45]);
    expect(clockShown(tester, 'range-start'), '19:10');
  });

  testWidgets('an unreadable value shows hints and picks fill both lists', (
    tester,
  ) async {
    await tester.pumpWidget(
      scopedApp(
        const Material(child: _Range('1212121212121212:00', '18:00')),
        InteractionSuite.scan,
      ),
    );
    await tester.pumpAndSettle();
    expect(clockShown(tester, 'range-start'), isNull);
    expect(find.byKey(const ValueKey('range-summary')), findsNothing);
    await pickClock(tester, 'range-start', 'hour', 9);
    expect(clockShown(tester, 'range-start'), '09:00');
  });
}
