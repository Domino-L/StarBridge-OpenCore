import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';
import 'package:starbridge_flutter/features/settings/notification_audio_panel.dart';
import 'package:starbridge_flutter/features/settings/notification_audio_controller.dart';
import 'package:starbridge_flutter/features/settings/notification_sources_connected_panel.dart';
import 'package:starbridge_flutter/features/settings/bridge_notification_sources.dart';
import 'package:starbridge_flutter/features/settings/notification_settings_sources.dart';
import 'package:starbridge_flutter/features/settings/notification_settings_models.dart';

import '../../features/settings/notification_audio_test.dart' show AudioFake;
import '../../features/settings/notification_sources_test.dart' as sources;
import '../../features/friends/social_layout_test.dart' show loadFonts;
import 'interaction_batch3ae_test.dart' show mount;

class HeldSources extends sources.Fake {
  final pending = Completer<NotificationSourcesValue>();
  @override
  Future<NotificationSourcesValue> read() {
    reads++;
    return pending.future;
  }
}

void main() {
  setUpAll(loadFonts);
  for (final suite in InteractionSuite.values) {
    testWidgets('$suite slider release uses latest input before next paint', (
      t,
    ) async {
      var changed = .2;
      double? ended;
      await mount(
        t,
        Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: 300,
            child: SuiteSlider(
              value: .2,
              onChanged: (v) => changed = v,
              onChangeEnd: (v) => ended = v,
            ),
          ),
        ),
        suite,
      );
      final rect = t.getRect(find.byType(SuiteSlider));
      final gesture = await t.startGesture(
        Offset(rect.right - 20, rect.center.dy),
      );
      await gesture.up();
      await t.pumpAndSettle();
      expect(changed, greaterThan(.8));
      expect(ended, changed);
      await t.pumpWidget(const SizedBox());
    });
    testWidgets('$suite audio controller replacement clears drag preview', (
      t,
    ) async {
      final a = NotificationAudioController(
        AudioFake()..value = const AudioPreferences(1, true, .65, true),
      );
      final b = NotificationAudioController(
        AudioFake()..value = const AudioPreferences(1, true, .2, true),
      );
      await a.refresh();
      await b.refresh();
      addTearDown(a.dispose);
      addTearDown(b.dispose);
      var current = a;
      late StateSetter update;
      await mount(
        t,
        StatefulBuilder(
          builder: (_, setState) {
            update = setState;
            return NotificationAudioPanel(controller: current);
          },
        ),
        suite,
      );
      final native = find.byKey(const Key('audio-volume'));
      final control = t.widget(native);
      if (control is Slider) {
        control.onChanged!(.8);
      } else if (control is SuiteSlider) {
        control.onChanged!(.8);
      }
      await t.pump();
      expect(find.text('80%'), findsOneWidget);
      update(() => current = b);
      await t.pump();
      expect(find.text('20%'), findsOneWidget);
      expect(find.text('80%'), findsNothing);
      await t.pumpWidget(const SizedBox());
    });
    testWidgets('$suite source port replacement rejects old read and events', (
      t,
    ) async {
      final a = HeldSources(), b = sources.Fake();
      var current = a as NotificationSourcesPort;
      var visible = false;
      late StateSetter update;
      await mount(
        t,
        StatefulBuilder(
          builder: (_, setState) {
            update = setState;
            return visible
                ? NotificationSourcesConnectedPanel(port: current)
                : const SizedBox();
          },
        ),
        suite,
      );
      update(() => visible = true);
      await t.pump();
      expect(a.reads, 1);
      update(() => current = b);
      await t.pump();
      await t.pumpAndSettle();
      expect(b.reads, 1);
      final old = NotificationSourcesValue(3, [
        for (final rule in b.value.sources)
          rule.copyWith(mode: NotificationSourceMode.doNotDisturb),
      ]);
      a.pending.complete(old);
      await t.pump();
      await t.pumpAndSettle();
      for (final row in t.widgetList<NotificationSourceRuleRow>(
        find.byType(NotificationSourceRuleRow),
      )) {
        expect(row.rule.mode, NotificationSourceMode.normal);
      }
      a.changes.add(null);
      await t.pump();
      await t.pumpAndSettle();
      expect(b.reads, 1);
      await t.pumpWidget(const SizedBox());
      a.dispose();
      b.dispose();
    });
  }
}
