import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/shell/widgets/attention_badge.dart';
import 'package:starbridge_flutter/design_system/icons/standard_icon.dart';
import 'package:starbridge_flutter/design_system/tokens/starbridge_tokens.dart';
import 'package:starbridge_flutter/features/friends/friend_message_action.dart';
import 'package:starbridge_flutter/features/friends/friends_section_navigation.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../features/friends/social_layout_test.dart' show loadFonts, size;
import 'interaction_batch3dc_actions_test.dart' show Fixture;
import 'interaction_batch3i_test.dart' show scopedApp;

Future<List<int>?> pixels(WidgetTester t, GlobalKey key) => t.runAsync(
  () async {
    final image =
        await (key.currentContext!.findRenderObject() as RenderRepaintBoundary)
            .toImage();
    final bytes = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!
        .buffer
        .asUint8List()
        .toList();
    image.dispose();
    return bytes;
  },
);

Future<void> save(WidgetTester t, GlobalKey key, String name) async {
  await t.runAsync(() async {
    final image =
        await (key.currentContext!.findRenderObject() as RenderRepaintBoundary)
            .toImage();
    final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!
        .buffer
        .asUint8List();
    image.dispose();
    final file = File('build/reviews/interaction-batch3dc/$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes);
  });
}

void main() {
  setUpAll(loadFonts);
  for (final suite in InteractionSuite.values) {
    for (final light in [false, true]) {
      for (final scale in [1.0, 2.0]) {
        for (final enabled in [false, true]) {
          testWidgets(
            '$suite light=$light scale=$scale enabled=$enabled native dimensions and press',
            (t) async {
              size(t, const Size(1400, 1000));
              final h = Fixture('remove');
              final frame = GlobalKey();
              var calls = 0;
              try {
                await h.mount(t, suite);
                h.owner.busy = !enabled;
                final child = Builder(
                  builder: (context) => RepaintBoundary(
                    key: frame,
                    child: Material(
                      color: Theme.of(context).scaffoldBackgroundColor,
                      child: SizedBox(
                        width: 1000,
                        height: 650,
                        child: Column(
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              children: [
                                OutlinedButton.icon(
                                  key: const Key('native-message'),
                                  onPressed: enabled ? () {} : null,
                                  icon: const StandardIcon(
                                    StandardIconSemantic.chatBubble,
                                    size: 16,
                                  ),
                                  label: const AttentionBadge(
                                    count: 12,
                                    child: Text('消息'),
                                  ),
                                ),
                                FriendMessageAction(
                                  controlKey: const Key('adapted-message'),
                                  label: '消息',
                                  unread: 12,
                                  onPressed: enabled ? () => calls++ : null,
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Expanded(
                              child: Row(
                                children: [
                                  SizedBox(
                                    width: 320,
                                    child: ListView(
                                      children: [
                                        ListTile(
                                          key: const Key('native-recent'),
                                          title: Text(
                                            'recent',
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodyMedium,
                                          ),
                                          trailing: const AttentionCount(
                                            count: 12,
                                          ),
                                          onTap: enabled ? () {} : null,
                                        ),
                                        const Divider(),
                                        for (final section
                                            in h.owner.snapshot!.groups.keys)
                                          ListTile(
                                            key: ValueKey(
                                              'native-${section.name}',
                                            ),
                                            title: Text(
                                              section.name,
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .bodyMedium,
                                            ),
                                            trailing: section.name == 'incoming'
                                                ? const AttentionCount(count: 0)
                                                : Text(
                                                    '${h.owner.snapshot!.groups[section]!.length}',
                                                  ),
                                            selected:
                                                h.owner.section == section,
                                            selectedTileColor: context
                                                .tokens
                                                .surfaces
                                                .selected
                                                .fill,
                                            selectedColor:
                                                context.tokens.colors.accent,
                                            onTap: enabled ? () {} : null,
                                          ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 20),
                                  SizedBox(
                                    width: 320,
                                    child: FriendsSectionNavigation(
                                      module: h.owner,
                                      label: (v) => v,
                                      onSection: (_) => calls++,
                                      onRecent: () => calls++,
                                      showRecent: true,
                                      recentUnread: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
                Widget app(bool reduce) => scopedApp(
                  MediaQuery(
                    data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                    child: Center(child: child),
                  ),
                  suite,
                  light: light,
                  reduce: reduce,
                );
                await t.pumpWidget(app(false));
                await t.pumpAndSettle();
                final expected = t.getSize(
                  find.byKey(const Key('native-message')),
                );
                expect(
                  t.getSize(find.byKey(const Key('adapted-message'))),
                  expected,
                );
                for (final name in [
                  'recent',
                  'friends',
                  'incoming',
                  'outgoing',
                  'blocked',
                ]) {
                  final old = t.getRect(find.byKey(Key('native-$name')));
                  final newer = t.getRect(
                    find.byKey(
                      Key(
                        name == 'recent'
                            ? 'friends-recent'
                            : 'friends-nav-$name',
                      ),
                    ),
                  );
                  expect(
                    newer.size,
                    old.size,
                    reason: '$name original tile size',
                  );
                  expect(
                    newer.top,
                    old.top,
                    reason: '$name no added padding/spacing',
                  );
                }
                final prefix =
                    '${suite.name}-${light ? 'light' : 'dark'}-${scale.toInt()}-${enabled ? 'enabled' : 'disabled'}';
                await save(t, frame, '$prefix-idle');
                if (enabled) {
                  final idle = await pixels(t, frame);
                  final down = await t.startGesture(
                    t.getCenter(find.byKey(const Key('adapted-message'))),
                  );
                  await t.pump(const Duration(milliseconds: 90));
                  expect(
                    await pixels(t, frame),
                    isNot(idle),
                    reason: 'active press must retain visible feedback',
                  );
                  expect(calls, 0);
                  await save(t, frame, '$prefix-press');
                  await down.up();
                  await t.pumpAndSettle();
                  expect(calls, 1);
                  await t.pumpWidget(app(true));
                  await t.pump();
                  await t.pump();
                  await save(t, frame, '$prefix-reduce');
                  final pressable = find.byKey(const Key('adapted-message'));
                  final before = await pixels(t, frame);
                  final reduced = await t.startGesture(t.getCenter(pressable));
                  await t.pump();
                  final immediate = await pixels(t, frame);
                  await t.pump(const Duration(milliseconds: 200));
                  expect(
                    await pixels(t, frame),
                    immediate,
                    reason: 'reduce has no timed press tail',
                  );
                  // Reduced feedback may be static; it must never invoke before release.
                  expect(before, isNotEmpty);
                  expect(calls, 1);
                  await reduced.up();
                  await t.pumpAndSettle();
                  expect(calls, 2);
                }
                expect(t.takeException(), isNull);
              } finally {
                await h.close(t);
              }
            },
          );
        }
      }
    }
  }
}
