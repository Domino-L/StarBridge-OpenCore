import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_compact_select.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_roster_display_options.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_roster_editor.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../design_system/interaction/interaction_batch3aa_test.dart'
    show open, select;
import '../../design_system/interaction/interaction_batch3i_test.dart'
    show scopedApp;

Map<String, Object?> _view(OverlayRosterDisplay display, {int revision = 3}) =>
    {
      'schemaVersion': 1,
      'revision': revision,
      'rows': [
        {'key': 'a', 'name': 'Member A', 'mode': 'auto'},
      ],
      'display': display.toWire(),
    };

class _DisplayPort implements OverlayRosterPort, OverlayRosterDisplayPort {
  OverlayRosterDisplay current = const OverlayRosterDisplay();
  final updates = <(int, OverlayRosterDisplay)>[];
  int revision = 3;
  // A closed stream means the account ended; keep it open like a live session.
  final _events = StreamController<void>.broadcast();
  @override
  Stream<void> get invalidations => _events.stream;
  @override
  Future<Map<String, Object?>> request([
    int? revision,
    String? key,
    String? mode,
  ]) async => _view(current, revision: this.revision);
  @override
  Future<Map<String, Object?>> updateDisplay(
    int revision,
    OverlayRosterDisplay display,
  ) async {
    updates.add((revision, display));
    current = display;
    this.revision++;
    return _view(current, revision: this.revision);
  }
}

class _PinOnlyPort implements OverlayRosterPort {
  // A closed stream means the account ended; keep it open like a live session.
  final _events = StreamController<void>.broadcast();
  @override
  Stream<void> get invalidations => _events.stream;
  @override
  Future<Map<String, Object?>> request([
    int? revision,
    String? key,
    String? mode,
  ]) async => _view(const OverlayRosterDisplay());
}

// The control key lands on the inner pressable; find the select by identity.
// Its callback is generic, so read it dynamically rather than through a cast.
bool _enabled(WidgetTester t, String identity) {
  final Object select = t.widget(
    find.byWidgetPredicate(
      (w) => w is StarBridgeCompactSelect && w.identity == identity,
    ),
  );
  return (select as dynamic).onSelected != null;
}

// Same host shell as the existing roster interaction tests.
Future<void> _mount(WidgetTester t, OverlayRosterPort port) async {
  final base = scopedApp(
    Center(child: OverlayRosterButton(port: port)),
    InteractionSuite.standard,
  ) as MaterialApp;
  await t.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: base.theme,
      locale: const Locale('en'),
      supportedLocales: base.supportedLocales,
      localizationsDelegates: base.localizationsDelegates,
      builder: base.builder,
      home: base.home,
    ),
  );
  await t.pumpAndSettle();
  await t.tap(find.byKey(const Key('overlay-roster-open')));
  await t.pumpAndSettle();
}

void main() {
  testWidgets('member overflow display is chosen in the roster dialog', (
    t,
  ) async {
    final port = _DisplayPort();
    await _mount(t, port);

    expect(find.byKey(const Key('overlay-roster-display')), findsOneWidget);
    expect(find.text('Member A'), findsOneWidget);
    expect(
      _enabled(t, 'overlay-roster-interval'),
      isFalse,
      reason: 'the page interval only applies while pages rotate',
    );

    await open(t, const Key('overlay-roster-overflow'), 'pointer');
    await t.pumpAndSettle();
    await select(t, 'overlay-roster-overflow', 'rotate', 'pointer');
    await t.pumpAndSettle();

    expect(port.updates, hasLength(1));
    expect(port.updates.single.$1, 3, reason: 'writes carry the read revision');
    expect(port.updates.single.$2.overflow, 'rotate');
    expect(port.updates.single.$2.rowLimit, 0);
    expect(port.updates.single.$2.rotationIntervalSeconds, 10);
    expect(_enabled(t, 'overlay-roster-interval'), isTrue);

    await open(t, const Key('overlay-roster-rows'), 'pointer');
    await t.pumpAndSettle();
    await select(t, 'overlay-roster-rows', 3, 'pointer');
    await t.pumpAndSettle();
    expect(
      port.updates.last.$1,
      4,
      reason: 'the next write uses the new revision',
    );
    expect(port.updates.last.$2.rowLimit, 3);
    expect(
      port.updates.last.$2.overflow,
      'rotate',
      reason: 'other options are kept',
    );
  });

  testWidgets('a port without display support keeps the member list only', (
    t,
  ) async {
    await _mount(t, _PinOnlyPort());
    expect(find.byKey(const Key('overlay-roster-display')), findsNothing);
    expect(find.text('Member A'), findsOneWidget);
  });

  test('display options from the Host are validated', () {
    expect(
      OverlayRosterDisplay.tryParse({
        'overflow': 'rotate',
        'rowLimit': 6,
        'rotationIntervalSeconds': 20,
      })?.rotationIntervalSeconds,
      20,
    );
    for (final invalid in [
      {'overflow': 'scroll', 'rowLimit': 6, 'rotationIntervalSeconds': 20},
      {'overflow': 'rotate', 'rowLimit': 13, 'rotationIntervalSeconds': 20},
      {'overflow': 'rotate', 'rowLimit': 6, 'rotationIntervalSeconds': 2},
      {'overflow': 'rotate', 'rowLimit': 6},
    ]) {
      expect(OverlayRosterDisplay.tryParse(invalid), isNull);
    }
  });
}
