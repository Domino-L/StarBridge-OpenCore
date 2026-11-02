import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';
import 'package:starbridge_flutter/platform/window/menu_read_feedback.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_loading.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_friends_view.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_comms_panel.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_comms_history.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_comms_directory.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_comms_view.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_feature_view.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_channel_panel.dart';

import '../../features/friends/social_layout_test.dart' show size;
import 'interaction_batch3i_test.dart' show scopedApp;
import 'interaction_batch3bw_test.dart' show frames;
import 'interaction_batch3cl_channel_test.dart' show state;

const kinds = [
  'friends',
  'private-loading',
  'history',
  'directory',
  'feature',
  'channel',
  'channel-room',
  'channel-org',
];
Widget subject(
  String kind,
  MenuReadFeedback? fact, {
  bool waiting = true,
  bool busy = false,
}) {
  final private = MenuCommsView(
    'ready',
    name: kind == 'history' ? '白鸦' : null,
    refreshing: waiting,
    readFeedback: fact,
    busy: busy,
  );
  if (kind == 'friends') {
    return MenuFriendsPanel(
      view: MenuFriendsView(
        'ready',
        refreshing: waiting,
        readFeedback: fact,
        busy: busy,
      ),
      onClose: () {},
    );
  }
  if (kind == 'private-loading') {
    return MenuCommsPanel(
      view: MenuCommsView(
        waiting ? 'loading' : 'ready',
        readFeedback: fact,
        busy: busy,
      ),
      active: false,
      onClose: () {},
      onAction: (_, _) {},
    );
  }
  if (kind == 'history') {
    return MenuCommsHistory(view: private, active: false, onAction: (_, _) {});
  }
  if (kind == 'directory') {
    return MenuCommsDirectory(
      view: private,
      query: '',
      group: 'all',
      onQuery: (_) {},
      onGroup: (_) {},
      onAction: (_, _) {},
    );
  }
  if (kind == 'feature') {
    return SingleChildScrollView(
      child: MenuFeaturePanel(
        view: MenuFeatureView(
          'ready',
          refreshing: waiting,
          readFeedback: fact,
          busy: busy,
        ),
        onAction: (_, _) {},
      ),
    );
  }
  final raw = {
    ...state(outbox: true),
    'refreshing': waiting,
    'busy': busy,
    'readFeedback': fact?.wire,
  };
  return MenuChannelPanel(
    view: MenuFeatureView.parse(raw),
    active: false,
    embeddedRoom: kind == 'channel-room',
    embeddedOrganization: kind == 'channel-org',
    onAction: (_, _) {},
  );
}

void main() {
  for (final suite in InteractionSuite.values) {
    for (final kind in kinds) {
      for (final source in [...MenuReadOrigin.values, null]) {
        testWidgets(
          '$suite $kind $source read projection controls slim wait, never busy alone',
          (t) async {
            size(t, const Size(1000, 1000));
            final semantics = t.ensureSemantics();
            final fact = source == null ? null : MenuReadFeedback(1, source);
            try {
              await t.pumpWidget(scopedApp(subject(kind, fact), suite));
              await t.pump();
              expect(find.byType(MenuLoading), findsOneWidget);
              final wait = find.descendant(
                of: find.byType(MenuLoading),
                matching: find.byType(SuiteBusyFrame),
              );
              expect(
                InteractionScope.of(t.element(wait)).reduceMotion,
                source != MenuReadOrigin.pointer,
              );
              final rect = t.getRect(find.byType(MenuLoading));
              expect(rect.width, greaterThan(100));
              expect(rect.height, closeTo(14, .1));
              final semantic = find.bySemanticsLabel(RegExp(r'^正在读取$'));
              expect(semantic, findsOneWidget);
              expect(
                t.getSemantics(semantic).getSemanticsData().value,
                isEmpty,
                reason: 'no invented percentage',
              );
              await t.pumpWidget(
                scopedApp(
                  subject(kind, fact, waiting: false, busy: true),
                  suite,
                ),
              );
              await t.pump();
              expect(
                find.byType(MenuLoading),
                findsNothing,
                reason: 'write busy is not read admission',
              );
              expect(t.takeException(), isNull);
            } finally {
              semantics.dispose();
              await t.pumpWidget(const SizedBox());
            }
          },
        );
      }
    }
    testWidgets(
      '$suite live local MediaQuery, suite and palette settle without relabeling source',
      (t) async {
        var localReduce = false;
        var selected = suite;
        var light = false;
        late StateSetter update;
        await t.pumpWidget(
          StatefulBuilder(
            builder: (_, setState) {
              update = setState;
              return scopedApp(
                Builder(
                  builder: (context) => MediaQuery(
                    data: MediaQuery.of(context)
                        .copyWith(disableAnimations: localReduce),
                    child: const MenuLoading(
                      feedback: MenuReadFeedback(9, MenuReadOrigin.pointer),
                    ),
                  ),
                ),
                selected,
                light: light,
              );
            },
          ),
        );
        final wait = find.byType(SuiteBusyFrame);
        await t.pump();
        expect(InteractionScope.of(t.element(wait)).reduceMotion, isFalse);
        update(() {
          localReduce = true;
          selected = InteractionSuite.glow;
          light = true;
        });
        await t.pump();
        await t.pump();
        final data = InteractionScope.of(t.element(wait));
        expect(data.reduceMotion, isTrue);
        expect(data.suite, InteractionSuite.glow);
        expect(data.palette.brightness, Brightness.light);
        update(() => localReduce = false);
        await t.pump();
        await t.pump();
        expect(InteractionScope.of(t.element(wait)).reduceMotion, isFalse);
        await t.pumpWidget(const SizedBox());
      },
    );
    for (final embed in ['channel', 'channel-room', 'channel-org']) {
      testWidgets(
        '$suite $embed uses raw request source while retaining ready content and draft',
        (t) async {
          size(t, const Size(900, 900));
          final raw = ValueNotifier({
            ...state(outbox: true),
            'readFeedback': const MenuReadFeedback(
              1,
              MenuReadOrigin.pointer,
            ).wire,
          });
          await t.pumpWidget(
            scopedApp(
              ValueListenableBuilder(
                valueListenable: raw,
                builder: (_, value, _) => MenuChannelPanel(
                  view: MenuFeatureView.parse(value),
                  active: false,
                  embeddedRoom: embed == 'channel-room',
                  embeddedOrganization: embed == 'channel-org',
                  onAction: (_, _) {},
                ),
              ),
              suite,
            ),
          );
          await frames(t, 2);
          final field = find.byKey(const ValueKey('menu-channel-draft'));
          await t.enterText(field, 'cached draft');
          await t.pump();
          final controller = t.widget<TextField>(field).controller!;
          raw.value = {
            ...state(outbox: true),
            'state': 'loading',
            'readFeedback': const MenuReadFeedback(
              2,
              MenuReadOrigin.keyboard,
            ).wire,
          };
          await t.pump();
          await t.pump();
          expect(find.text('准备好后在奥里森集合。'), findsOneWidget);
          expect(controller.text, 'cached draft');
          expect(
            InteractionScope.of(t.element(find.byType(SuiteBusyFrame)))
                .reduceMotion,
            isTrue,
          );
          raw.value = {
            ...raw.value,
            'readFeedback': const MenuReadFeedback(
              3,
              MenuReadOrigin.pointer,
            ).wire,
          };
          await t.pump();
          await t.pump();
          expect(
            InteractionScope.of(t.element(find.byType(SuiteBusyFrame)))
                .reduceMotion,
            isFalse,
          );
          await t.enterText(field, 'still editable');
          await t.pump();
          expect(controller.text, 'still editable');
          await t.pumpWidget(const SizedBox());
          raw.dispose();
        },
      );
    }
  }
}
