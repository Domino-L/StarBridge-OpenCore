import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/features/tools/exec_hangar_menu_widget_button.dart';
import 'package:starbridge_flutter/features/tools/exec_hangar_waiting.dart';
import 'package:starbridge_flutter/platform/window/menu_window_preferences.dart';

import 'interaction_batch3i_test.dart' show scopedApp;
import 'interaction_batch3dm_test.dart' show act;
import 'interaction_batch3dn_test.dart' show sourceOf, waitData;
import '../../features/friends/social_layout_test.dart' show loadFonts, size;

class Preferences implements MenuWindowPreferencesPort {
  MenuWindowPreferences current = MenuWindowPreferences.defaults;
  Completer<MenuWindowPreferences>? readGate, saveGate;
  int reads = 0;
  final saves = <MenuWindowPreferences>[];
  @override
  Future<MenuWindowPreferences> read() {
    reads++;
    return readGate?.future ?? Future.value(current);
  }

  @override
  Future<MenuWindowPreferences> save(MenuWindowPreferences value) {
    saves.add(value);
    return (saveGate?.future ?? Future.value(value)).then((next) {
      current = next;
      return next;
    });
  }
}

void main() {
  setUpAll(loadFonts);
  for (final suite in InteractionSuite.values) {
    for (final source in ['pointer', 'keyboard', 'reader']) {
      testWidgets(
        '$suite $source menu pin waits through pre-read and CAS, refuses without optimistic success',
        (t) async {
          final semantics = t.ensureSemantics();
          try {
            size(t, const Size(600, 700));
            final port = Preferences()..readGate = Completer();
            Widget host() => scopedApp(
              Center(child: ExecHangarMenuWidgetButton(port: port)),
              suite,
            );
            await t.pumpWidget(host());
            await t.pump();
            expect(port.reads, 1);
            expect(
              t
                  .widget<ExecHangarWaiting>(find.byType(ExecHangarWaiting))
                  .opening,
              isTrue,
            );
            port.readGate!.complete(MenuWindowPreferences.defaults);
            await t.pumpAndSettle();
            port.readGate = null;
            final context = t.element(find.byType(ExecHangarMenuWidgetButton)),
                strings = AppStrings.of(context),
                target = find.byKey(const Key('exec-pin-menu'));
            port.readGate = Completer();
            port.saveGate = Completer();
            await act(
              t,
              target,
              source,
              strings.text('execHangar.widgetRemove'),
            );
            await t.pump();
            final waiting = find.byType(ExecHangarWaiting),
                phase = t.widget(waiting).key;
            expect(
              t.widget<ExecHangarWaiting>(waiting).source,
              sourceOf(source),
            );
            expect(t.widget<ExecHangarWaiting>(waiting).opening, isFalse);
            expect(waitData(t, waiting).reduceMotion, source != 'pointer');
            expect(port.saves, isEmpty);
            expect(port.reads, 2);
            expect(
              find.text(strings.text('execHangar.widgetSaving')),
              findsNWidgets(2),
            );
            await t.pumpWidget(host());
            await t.pump();
            expect(t.widget(waiting).key, phase);
            expect(port.reads, 2);
            final fresh = MenuWindowPreferences(
              7,
              {...port.current.layout},
              {...port.current.settings, 'showClock': false},
            );
            port.readGate!.complete(fresh);
            await t.pump();
            await t.pump();
            expect(port.saves, hasLength(1));
            expect(port.saves.single.revision, 7);
            expect(port.saves.single.layout, fresh.layout);
            expect(port.saves.single.settings['showClock'], isFalse);
            expect(
              (port.saves.single.settings['widgets'] as Map)['hangar'],
              isFalse,
            );
            expect(
              (port.saves.single.settings['widgets'] as Map)['position'],
              (fresh.settings['widgets'] as Map)['position'],
            );
            expect(t.widget(waiting).key, phase);
            port.saveGate!.completeError(StateError('CAS rejected'));
            await t.pumpAndSettle();
            expect(waiting, findsNothing);
            expect(
              find.text(strings.text('execHangar.widgetFailed')),
              findsOneWidget,
            );
            expect(
              find.text(strings.text('execHangar.widgetRemove')),
              findsOneWidget,
            );
            port.readGate = null;
            port.current = MenuWindowPreferences(
              8,
              fresh.layout,
              fresh.settings,
            );
            port.saveGate = Completer();
            await act(
              t,
              target,
              source,
              strings.text('execHangar.widgetRemove'),
            );
            await t.pump();
            await t.pump();
            expect(port.saves, hasLength(2));
            expect(port.saves.last.revision, 8);
            expect(
              t.widget<ExecHangarWaiting>(waiting).source,
              sourceOf(source),
            );
            port.saveGate!.complete(
              MenuWindowPreferences(
                9,
                port.saves.last.layout,
                port.saves.last.settings,
              ),
            );
            await t.pumpAndSettle();
            expect(waiting, findsNothing);
            expect(
              find.text(strings.text('execHangar.widgetAdd')),
              findsOneWidget,
            );
            port.saveGate = Completer();
            await act(t, target, source, strings.text('execHangar.widgetAdd'));
            await t.pump();
            await t.pump();
            expect(port.saves, hasLength(3));
            await t.pumpWidget(const SizedBox());
            port.saveGate!.complete(port.saves.last);
            await t.pump();
            expect(waiting, findsNothing);
            expect(t.takeException(), isNull);
          } finally {
            semantics.dispose();
          }
        },
      );
    }
  }
}
