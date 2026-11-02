import 'dart:async';
import 'dart:io';
import 'dart:ui' show ImageByteFormat, SemanticsAction;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:starbridge_interaction/starbridge_interaction.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_compact_select.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_activation_origin.dart';
import 'package:starbridge_flutter/features/communities/community_ships_panel.dart';
import 'package:starbridge_flutter/features/communities/community_ships_port.dart';
import 'package:starbridge_flutter/features/communities/community_settings_workspace.dart';
import 'package:starbridge_flutter/features/communities/community_profile_dialog.dart';
import 'package:starbridge_flutter/features/communities/community_profile_port.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_roster_editor.dart';

import 'interaction_batch3ac_test.dart' show Live, LiveState;
import 'interaction_batch3aa_test.dart' show open, select;
import 'interaction_batch3m_test.dart' show keyPress;
import '../../features/friends/social_layout_test.dart' show loadFonts, size;
import '../../features/communities/community_image_test_support.dart'
    show settleCommunityImages;
import '../../features/communities/community_settings_workspace_test.dart'
    show SettingsTestPort, target;
import '../../features/communities/community_ships_test.dart' show shipRow;

const choices = [
  StarBridgeSelectOption(value: 'a', label: 'A'),
  StarBridgeSelectOption(value: 'b', label: 'A longer label'),
];

Future<LiveState> mount(
  WidgetTester t,
  Widget child,
  InteractionSuite suite, {
  double width = 1000,
  double scale = 1,
  GlobalKey? capture,
}) async {
  size(t, const Size(1280, 1000));
  final key = GlobalKey<LiveState>();
  final app = Live(
    Align(
      alignment: Alignment.topCenter,
      child: SizedBox(width: width, height: 960, child: child),
    ),
    suite,
    key: key,
    scale: scale,
  );
  await t.pumpWidget(
    capture == null ? app : RepaintBoundary(key: capture, child: app),
  );
  await settleCommunityImages(t);
  return key.currentState!;
}

Finder compact(Object identity) => find.byWidgetPredicate(
  (w) => w is StarBridgeCompactSelect<String> && w.identity == identity,
);

Future<void> choose(
  WidgetTester t,
  Object identity,
  String value,
  String source, {
  bool settle = true,
}) async {
  final config = t.widget<StarBridgeCompactSelect<String>>(compact(identity));
  final target = find.byKey(config.controlKey!);
  if (source == 'reader') {
    await t.ensureVisible(target);
    await t.pumpAndSettle();
    final node = t.getSemantics(target);
    expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
    t.binding.renderViews.single.owner!.semanticsOwner!.performAction(
      node.id,
      SemanticsAction.tap,
    );
    await t.pump();
    await t.pump();
  } else {
    await open(t, config.controlKey!, source);
  }
  await t.pumpAndSettle();
  final row = find.byKey(ValueKey<Object>((identity, value)));
  await t.ensureVisible(row);
  await t.pumpAndSettle();
  if (source == 'reader') {
    final node = t.getSemantics(row);
    t.binding.renderViews.single.owner!.semanticsOwner!.performAction(
      node.id,
      SemanticsAction.tap,
    );
    await t.pump();
    await t.pump();
  } else {
    await select(t, identity, value, source);
  }
  if (settle) await settleCommunityImages(t);
}

Future<void> action(
  WidgetTester t,
  Key key,
  String source, {
  bool settle = true,
}) async {
  final target = find.byKey(key);
  await t.ensureVisible(target);
  if (source == 'pointer') {
    await t.tap(target);
  } else if (source == 'keyboard') {
    await keyPress(t, target);
  } else {
    final node = t.getSemantics(target);
    expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
    t.binding.renderViews.single.owner!.semanticsOwner!.performAction(
      node.id,
      SemanticsAction.tap,
    );
  }
  await t.pump();
  await t.pump();
  if (settle) await t.pumpAndSettle();
}

class Ships implements CommunityShipsPort {
  final changes = StreamController<void>.broadcast(sync: true);
  final requests =
      <
        ({
          String target,
          int offset,
          String? revision,
          CommunityShipQuery query,
        })
      >[];
  @override
  Stream<void> get invalidations => changes.stream;
  @override
  bool get shipsAvailable => true;
  @override
  Future<CommunityShipsPage> readShips(
    String targetRef, {
    int offset = 0,
    String? revision,
    CommunityShipQuery? query,
  }) async {
    requests.add((
      target: targetRef,
      offset: offset,
      revision: revision,
      query: query!,
    ));
    return CommunityShipsPage.parse({
      'schemaVersion': 1,
      'queryVersion': 2,
      'query': query.toPayload(),
      'targetRef': targetRef,
      'revision': 'B' * 64,
      'offset': 0,
      'totalCount': 1,
      'matchedCount': 1,
      'next': null,
      'ships': [shipRow()..['ownerHasAvatar'] = false],
    });
  }
}

class SettingsPort extends SettingsTestPort {
  int saves = 0;
  @override
  Future<CommunityProfileOutcome> saveProfile(
    String requestId,
    String editRef,
    Map<String, Object?> values,
  ) {
    saves++;
    return super.saveProfile(requestId, editRef, values);
  }
}

class Roster implements OverlayRosterPort {
  final events = StreamController<void>.broadcast(sync: true);
  final writes = <(int, String, String, InteractionSource)>[];
  int reads = 0, revision = 0;
  String mode = 'auto';
  bool empty = false;
  Completer<Map<String, Object?>>? hold;
  @override
  Stream<void> get invalidations => events.stream;
  Map<String, Object?> data() => {
    'schemaVersion': 1,
    'revision': revision,
    'rows': empty
        ? []
        : [
            {'key': 'a', 'name': 'Member A', 'mode': mode},
            {'key': 'b', 'name': 'Member B', 'mode': 'auto'},
          ],
  };
  @override
  Future<Map<String, Object?>> request([
    int? version,
    String? key,
    String? next,
  ]) async {
    if (version == null) {
      reads++;
      return data();
    }
    writes.add((version, key!, next!, currentStarBridgeActivationSource));
    if (hold != null) return hold!.future;
    mode = next;
    revision++;
    return data();
  }
}

void main() {
  setUpAll(loadFonts);
  for (final suite in InteractionSuite.values) {
    for (final scale in [1.0, 2.0]) {
      for (final expanded in [false, true]) {
        testWidgets(
          'dense native geometry typography icon remain exact $suite $scale $expanded',
          (t) async {
            const style = TextStyle(fontSize: 18, fontWeight: FontWeight.w500);
            const icon = Icon(Icons.keyboard_arrow_down, size: 18);
            Widget decorated(Widget child, Key key) => SizedBox(
              key: key,
              width: expanded ? 175 : 700,
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Choice',
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                ),
                child: DropdownButtonHideUnderline(child: child),
              ),
            );
            await mount(
              t,
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  decorated(
                    StarBridgeCompactSelect<String>(
                      identity: 'dense',
                      semanticLabel: 'Choice',
                      options: choices,
                      value: 'b',
                      onSelected: (_, _) {},
                      isDense: true,
                      isExpanded: expanded,
                      style: style,
                      icon: icon,
                      selectedMaxLines: 1,
                      selectedOverflow: TextOverflow.ellipsis,
                    ),
                    const Key('new'),
                  ),
                  decorated(
                    DropdownButton<String>(
                      value: 'b',
                      isDense: true,
                      isExpanded: expanded,
                      style: style,
                      icon: icon,
                      items: [
                        for (final c in choices)
                          DropdownMenuItem(
                            value: c.value,
                            child: Text(
                              c.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: (_) {},
                    ),
                    const Key('original'),
                  ),
                ],
              ),
              suite,
              scale: scale,
            );
            final actual = t.getSize(find.byKey(const Key('new'))),
                original = t.getSize(find.byKey(const Key('original')));
            expect(actual.width, closeTo(original.width, .01));
            expect(actual.height, closeTo(original.height, .01));
            expect(t.takeException(), isNull);
            await t.pumpWidget(const SizedBox());
          },
        );
      }
    }

    for (final source in ['pointer', 'keyboard', 'reader']) {
      testWidgets(
        'compact callback preserves explicit and ambient source across await $suite $source',
        (t) async {
          final semantics = t.ensureSemantics();
          try {
            final calls = <(String, InteractionSource, InteractionSource)>[],
                later = <InteractionSource>[];
            await mount(
              t,
              Center(
                child: StarBridgeCompactSelect<String>(
                  identity: 'source',
                  controlKey: const Key('source-control'),
                  semanticLabel: 'Choice',
                  options: choices,
                  value: 'a',
                  onSelected: (v, s) {
                    calls.add((v, s, currentStarBridgeActivationSource));
                    unawaited(
                      Future<void>.value().then(
                        (_) => later.add(currentStarBridgeActivationSource),
                      ),
                    );
                  },
                ),
              ),
              suite,
            );
            await choose(t, 'source', 'b', source);
            await choose(t, 'source', 'b', source);
            final origin = source == 'pointer'
                ? InteractionSource.pointer
                : InteractionSource.keyboard;
            expect(calls, [('b', origin, origin), ('b', origin, origin)]);
            expect(later, [origin, origin]);
            expect(
              t
                  .widget<StarBridgeCompactSelect<String>>(compact('source'))
                  .value,
              'a',
            );
            await t.pumpWidget(const SizedBox());
          } finally {
            semantics.dispose();
          }
        },
      );

      testWidgets(
        'organization ship sort reaches original scoped read query $suite $source',
        (t) async {
          final semantics = t.ensureSemantics();
          try {
            final port = Ships();
            addTearDown(port.changes.close);
            await mount(
              t,
              CommunityShipsPanel(
                port: port,
                targetRef: 'a' * 32,
                name: 'Ships',
                onBack: () {},
              ),
              suite,
            );
            await choose(t, 'community-ships-sort', 'name', source);
            expect(port.requests, hasLength(2));
            final q = port.requests.last;
            expect(q.target, 'a' * 32);
            expect(q.offset, 0);
            expect(q.query.sort, 'name');
            expect(q.query.descending, isFalse);
            expect(t.takeException(), isNull);
            await t.pumpWidget(const SizedBox());
          } finally {
            semantics.dispose();
          }
        },
      );

      testWidgets(
        'organization category refusal retains same edited profile $suite $source',
        (t) async {
          final semantics = t.ensureSemantics();
          try {
            final port = SettingsPort();
            addTearDown(port.close);
            final workspace = await port.readWorkspace(target, '', 0);
            await mount(
              t,
              CommunitySettingsWorkspace(
                port: port,
                workspace: workspace,
                targetRef: target,
                onMembers: () {},
                hasDangerActions: false,
                dangerActions: const SizedBox(),
              ),
              suite,
              width: 720,
            );
            await choose(t, 'community-settings-category', 'profile', source);
            final editor = t.state<CommunityProfileDialogState>(
              find.byType(CommunityProfileDialog),
            );
            final description = find.byWidgetPredicate(
              (w) =>
                  w is TextFormField &&
                  w.key.toString().contains('-description'),
            );
            await t.ensureVisible(description);
            await t.enterText(description, 'Keep this draft');
            await settleCommunityImages(t);
            await choose(t, 'community-settings-category', 'overview', source);
            await t.tap(find.byKey(const Key('profile-leave-stay')));
            await settleCommunityImages(t);
            expect(
              t.state<CommunityProfileDialogState>(
                find.byType(CommunityProfileDialog),
              ),
              same(editor),
            );
            expect(editor.model.fields['description'], 'Keep this draft');
            expect(editor.model.dirty, isTrue);
            expect(port.saves, 0);
            expect(
              t
                  .widget<StarBridgeCompactSelect<String>>(
                    compact('community-settings-category'),
                  )
                  .value,
              'profile',
            );
            expect(t.takeException(), isNull);
            await t.pumpWidget(const SizedBox());
          } finally {
            semantics.dispose();
          }
        },
      );

      testWidgets(
        'roster member choice keeps exact revision identity and source $suite $source',
        (t) async {
          final semantics = t.ensureSemantics();
          try {
            final port = Roster();
            addTearDown(port.events.close);
            await mount(
              t,
              Center(child: OverlayRosterButton(port: port)),
              suite,
            );
            await action(t, const Key('overlay-roster-open'), source);
            await choose(t, ('overlay-roster-mode', 'a'), 'pin', source);
            final origin = source == 'pointer'
                ? InteractionSource.pointer
                : InteractionSource.keyboard;
            expect(port.writes, [(0, 'a', 'pin', origin)]);
            expect(port.reads, 1);
            expect(
              t
                  .widget<StarBridgeCompactSelect<String>>(
                    compact(('overlay-roster-mode', 'a')),
                  )
                  .value,
              'pin',
            );
            expect(
              t
                  .widget<StarBridgeCompactSelect<String>>(
                    compact(('overlay-roster-mode', 'b')),
                  )
                  .value,
              'auto',
            );
            await action(t, const Key('overlay-roster-close'), source);
            expect(find.text('Member A'), findsNothing);
            expect(t.takeException(), isNull);
            await t.pumpWidget(const SizedBox());
          } finally {
            semantics.dispose();
          }
        },
      );
    }

    testWidgets(
      'roster pending failure does not select optimistically or replay $suite',
      (t) async {
        final port = Roster()..hold = Completer<Map<String, Object?>>();
        addTearDown(port.events.close);
        final live = await mount(
          t,
          Center(child: OverlayRosterButton(port: port)),
          suite,
        );
        await action(t, const Key('overlay-roster-open'), 'keyboard');
        await choose(
          t,
          ('overlay-roster-mode', 'a'),
          'pin',
          'keyboard',
          settle: false,
        );
        expect(port.writes, hasLength(1));
        expect(port.mode, 'auto');
        expect(compact(('overlay-roster-mode', 'a')), findsNothing);
        live.change(() {
          live.reduce = true;
          live.light = true;
        });
        await t.pump();
        await t.pump();
        port.hold!.completeError(StateError('refused'));
        await t.pumpAndSettle();
        expect(port.mode, 'auto');
        expect(port.writes, hasLength(1));
        expect(find.text('Member A'), findsNothing);
        await action(t, const Key('overlay-roster-close'), 'keyboard');
        await t.pumpWidget(const SizedBox());
      },
    );

    testWidgets('roster close ignores delayed write response $suite', (
      t,
    ) async {
      final port = Roster()..hold = Completer<Map<String, Object?>>();
      addTearDown(port.events.close);
      await mount(t, Center(child: OverlayRosterButton(port: port)), suite);
      await action(t, const Key('overlay-roster-open'), 'keyboard');
      await choose(
        t,
        ('overlay-roster-mode', 'a'),
        'pin',
        'keyboard',
        settle: false,
      );
      await action(
        t,
        const Key('overlay-roster-close'),
        'keyboard',
        settle: false,
      );
      port.hold!.complete({
        'schemaVersion': 1,
        'revision': 1,
        'rows': [
          {'key': 'a', 'name': 'Old member', 'mode': 'pin'},
        ],
      });
      await t.pumpAndSettle();
      expect(find.text('Old member'), findsNothing);
      expect(port.writes, hasLength(1));
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    });

    testWidgets(
      'roster invalidation supersedes delayed write without old rows $suite',
      (t) async {
        final port = Roster()..hold = Completer<Map<String, Object?>>();
        addTearDown(port.events.close);
        await mount(t, Center(child: OverlayRosterButton(port: port)), suite);
        await action(t, const Key('overlay-roster-open'), 'keyboard');
        await choose(
          t,
          ('overlay-roster-mode', 'a'),
          'pin',
          'keyboard',
          settle: false,
        );
        port.empty = true;
        port.events.add(null);
        await t.pumpAndSettle();
        port.hold!.complete({
          'schemaVersion': 1,
          'revision': 1,
          'rows': [
            {'key': 'a', 'name': 'Old member', 'mode': 'pin'},
          ],
        });
        await t.pumpAndSettle();
        expect(find.text('Old member'), findsNothing);
        expect(port.reads, 2);
        expect(port.writes, hasLength(1));
        await action(t, const Key('overlay-roster-close'), 'keyboard');
        await t.pumpWidget(const SizedBox());
      },
    );
  }

  for (final suite in [InteractionSuite.scan, InteractionSuite.glow]) {
    testWidgets('roster full dialog review with real overlay $suite', (
      t,
    ) async {
      final port = Roster();
      addTearDown(port.events.close);
      final capture = GlobalKey();
      await mount(
        t,
        Center(child: OverlayRosterButton(port: port)),
        suite,
        capture: capture,
      );
      await action(t, const Key('overlay-roster-open'), 'pointer');
      final c = t.widget<StarBridgeCompactSelect<String>>(
        compact(('overlay-roster-mode', 'a')),
      );
      await open(t, c.controlKey!, 'pointer');
      await t.pumpAndSettle();
      await t.pump(const Duration(milliseconds: 500));
      final rectangles = [
        for (final mode in ['auto', 'pin', 'exclude'])
          t.getRect(find.byKey(ValueKey<Object>((c.identity, mode)))),
      ];
      final boundary =
          capture.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      await t.runAsync(() async {
        final image = await boundary.toImage();
        final data = await image.toByteData(format: ImageByteFormat.png);
        final raw = (await image.toByteData(format: ImageByteFormat.rawRgba))!
            .buffer
            .asUint8List();
        final counts = <int>[];
        for (final rect in rectangles) {
          var count = 0;
          for (var y = rect.top.ceil() + 4; y < rect.bottom.floor() - 4; y++) {
            for (
              var x = rect.left.ceil() + 10;
              x < rect.right.floor() - 10;
              x++
            ) {
              final n = (y * image.width + x) * 4;
              if (raw[n] >= 125 &&
                  raw[n] <= 175 &&
                  raw[n + 1] >= 145 &&
                  raw[n + 1] <= 190 &&
                  raw[n + 2] >= 150 &&
                  raw[n + 2] <= 200 &&
                  raw[n + 3] >= 240) {
                count++;
              }
            }
          }
          counts.add(count);
        }
        expect(
          counts,
          everyElement(greaterThan(5)),
          reason: 'Each member mode must paint real foreground text.',
        );
        Directory('build/reviews/interaction-batch3ae')
            .createSync(recursive: true);
        File('build/reviews/interaction-batch3ae/${suite.name}-roster.png')
            .writeAsBytesSync(data!.buffer.asUint8List());
        image.dispose();
      });
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    });
  }
}
