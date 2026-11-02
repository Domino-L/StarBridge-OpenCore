import 'dart:async';
import 'dart:io';
import 'dart:ui' show ImageByteFormat, SemanticsAction;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_dialog.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_passive_count.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_activation_origin.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_icon_action.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_action_row.dart';
import 'package:starbridge_flutter/design_system/icons/standard_icon.dart';
import 'package:starbridge_flutter/features/communities/community_compact_header.dart';
import 'package:starbridge_flutter/features/communities/community_workspace_view.dart';
import 'package:starbridge_flutter/features/communities/community_workspace_port.dart';
import 'package:starbridge_flutter/features/communities/community_section_navigation.dart';
import 'package:starbridge_flutter/features/communities/community_ownership_exit_dialog.dart';
import 'package:starbridge_flutter/features/communities/community_disband_dialog.dart';
import 'package:starbridge_flutter/features/communities/example_communities.dart';
import 'package:starbridge_flutter/features/communities/community_chat_panel.dart';

import 'interaction_batch3ae_test.dart' show mount;
import 'interaction_batch3ae_test.dart' as shared show action;
import '../../features/communities/community_workspace_test.dart'
    show WorkspaceTestPort, workspacePayload;
import '../../features/communities/community_image_test_support.dart'
    show settleCommunityImages;
import '../../features/friends/social_layout_test.dart' show loadFonts;

const target = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const exampleTarget = '00000000000000000000000000000002';

class Port extends WorkspaceTestPort {
  final calls = <(String, String, int, InteractionSource)>[];
  Completer<CommunityWorkspace>? pending;
  bool fail = false;
  @override
  Future<CommunityWorkspace> readWorkspace(
    String ref,
    String query,
    int offset,
  ) {
    calls.add((ref, query, offset, currentStarBridgeActivationSource));
    if (fail) {
      return Future.error(const FormatException('read rejected'));
    }
    final payload = workspacePayload(target: ref, query: query);
    final member = (payload['members'] as List).single as Map;
    return pending?.future ??
        Future.value(
          CommunityWorkspace.parse({
            ...payload,
            'offset': offset,
            'next': offset == 0 ? 20 : null,
            'totalCount': 21,
            'matchedCount': 21,
            'members': [
              for (var i = offset; i < (offset + 20).clamp(0, 21); i++)
                {...member, 'memberRef': i.toRadixString(16).padLeft(32, '0')},
            ],
          }),
        );
  }
}

Widget workspace(
  CommunityWorkspacePort port, {
  Key? key,
  String ref = target,
}) => CommunityWorkspaceView(
  key: key,
  port: port,
  targetRef: ref,
  organizationKey: 'same-organization',
);
Finder dialog() => find.byKey(const Key('community-details-dialog'));
Future<void> action(
  WidgetTester t,
  Key key,
  String source, {
  bool settle = true,
}) async {
  // A zero-duration ensureVisible updates ScrollPosition immediately, but its
  // layout and any pending editor caret scroll must settle before hit-testing.
  await t.ensureVisible(find.byKey(key));
  if (settle) {
    await t.pumpAndSettle();
  } else {
    // Lay out the requested scroll without waiting for unrelated busy loops.
    await t.pump();
    await t.pump();
  }
  final icons = find.byWidgetPredicate(
    (w) => w is StarBridgeIconAction && w.controlKey == key,
  );
  final rows = find.byWidgetPredicate(
    (w) => w is StarBridgeActionRow && w.controlKey == key,
  );
  final tiles = find.descendant(
    of: find.byKey(key),
    matching: find.byType(ListTile),
  );
  if (source == 'keyboard' &&
      rows.evaluate().isNotEmpty &&
      tiles.evaluate().isNotEmpty) {
    await t.ensureVisible(tiles.first);
    // Standard rows contain a non-focusable native InkWell below their
    // keyboard owner. Target the real owner instead of that inner Focus.
    final detectors = find.descendant(
      of: find.byKey(key),
      matching: find.byType(FocusableActionDetector),
    );
    final owner = detectors.evaluate().isEmpty
        ? null
        : t.widget<FocusableActionDetector>(detectors.first).focusNode;
    (owner ?? Focus.of(t.element(tiles.first))).requestFocus();
    await t.pump();
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pump();
    await t.pump();
    if (settle) {
      await settleCommunityImages(t);
    }
    return;
  }
  if (source == 'keyboard' && icons.evaluate().isNotEmpty) {
    final leaf = find
        .descendant(of: find.byKey(key), matching: find.byType(StandardIcon))
        .first;
    await t.ensureVisible(leaf);
    Focus.of(t.element(leaf)).requestFocus();
    await t.pump();
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pump();
    await t.pump();
    if (settle) {
      await settleCommunityImages(t);
    }
  } else {
    await shared.action(t, key, source, settle: settle);
  }
}

Future<void> inside(WidgetTester t, Key key, String source) async {
  // Header and modal may deliberately expose the same copy command key.
  final finder = find.descendant(of: dialog(), matching: find.byKey(key));
  await t.ensureVisible(finder);
  await t.pumpAndSettle();
  if (source == 'pointer') {
    await t.tap(finder);
  } else if (source == 'keyboard') {
    final text = find.descendant(of: finder, matching: find.byType(Text)).first;
    Focus.of(t.element(text)).requestFocus();
    await t.pump();
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
  } else {
    final node = t.getSemantics(finder);
    t.binding.renderViews.single.owner!.semanticsOwner!.performAction(
      node.id,
      SemanticsAction.tap,
    );
  }
  await settleCommunityImages(t);
}

void main() {
  setUpAll(loadFonts);
  for (final source in ['pointer', 'keyboard', 'reader']) {
    testWidgets(
      'member search then pagination keeps controls accessible $source',
      (t) async {
        final semantics = t.ensureSemantics(), port = Port();
        addTearDown(port.changes.close);
        try {
          await mount(
            t,
            workspace(port),
            InteractionSuite.standard,
            width: 600,
          );
          expect(
            t
                .widget<TextField>(
                  find.byKey(const Key('community-member-search')),
                )
                .decoration
                ?.labelText,
            '搜索成员、呼号或职务',
          );
          expect(
            find.byKey(const Key('community-member-filter-online')),
            findsNothing,
          );
          expect(
            t
                .widget<ButtonStyleButton>(
                  find.byKey(const Key('community-member-previous-page')),
                )
                .onPressed,
            isNull,
          );
          await t.enterText(
            find.byKey(const Key('community-member-search')),
            'query',
          );
          await action(t, const Key('community-member-search-submit'), source);
          expect(port.calls.last.$2, 'query');
          final owner = find.ancestor(
            of: find.byKey(const Key('community-member-rows')),
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is Scrollable &&
                  axisDirectionToAxis(widget.axisDirection) == Axis.vertical,
            ),
          );
          expect(owner, findsOneWidget);
          await t.scrollUntilVisible(
            find.byKey(const Key('community-member-next-page')),
            500,
            scrollable: owner,
          );
          await action(t, const Key('community-member-next-page'), source);
          expect(port.calls.last.$3, 20);
          expect(
            port.calls.last.$4,
            source == 'pointer'
                ? InteractionSource.pointer
                : InteractionSource.keyboard,
          );
          expect(t.takeException(), isNull);
        } finally {
          await t.pumpWidget(const SizedBox());
          semantics.dispose();
        }
      },
    );
  }
  for (final suite in InteractionSuite.values) {
    for (final source in ['pointer', 'keyboard', 'reader']) {
      testWidgets(
        'workspace compact expand details copy search page and source $suite $source',
        (t) async {
          final semantics = t.ensureSemantics(), port = Port();
          final clipboard = <String>[];
          addTearDown(port.changes.close);
          t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.platform,
            (call) async {
              if (call.method == 'Clipboard.setData') {
                clipboard.add((call.arguments as Map)['text'] as String);
              }
              return null;
            },
          );
          addTearDown(
            () => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
              SystemChannels.platform,
              null,
            ),
          );
          try {
            await mount(t, workspace(port), suite, width: 600);
            final rowState = t.state(find.byType(CommunityWorkspaceView));
            await action(t, const Key('community-header-expand'), source);
            if (source == 'keyboard') {
              final icon = find
                  .descendant(
                    of: find.byKey(const Key('community-header-copy-contact')),
                    matching: find.byType(StandardIcon),
                  )
                  .first;
              Focus.of(t.element(icon)).requestFocus();
              await t.pump();
              await t.sendKeyEvent(LogicalKeyboardKey.enter);
              await settleCommunityImages(t);
            } else {
              await action(
                t,
                const Key('community-header-copy-contact'),
                source,
              );
            }
            expect(clipboard.last, 'organization-contact');
            await action(t, const Key('community-copy-all-contacts'), source);
            expect(clipboard.last, contains('Discord：organization-contact'));
            expect(clipboard.last, contains('https://example.org'));
            await action(t, const Key('community-open-details'), source);
            final route =
                ModalRoute.of(t.element(dialog()))! as StarBridgeDialogRoute;
            expect(route.instant, source != 'pointer');
            expect(find.text('Members only details'), findsWidgets);
            await inside(t, const Key('community-copy-all-contacts'), source);
            expect(clipboard.last, contains('Discord：organization-contact'));
            await inside(
              t,
              const Key('community-workspace-details-close'),
              source,
            );
            await action(t, const Key('community-header-collapse'), source);
            await t.enterText(
              find.byKey(const Key('community-member-search')),
              ' retained search ',
            );
            await action(
              t,
              const Key('community-member-search-submit'),
              source,
            );
            expect(port.calls.last.$2, 'retained search');
            await t.scrollUntilVisible(
              find.byKey(const Key('community-member-next-page')),
              500,
              scrollable: find
                  .descendant(
                    of: find.byType(ListView).first,
                    matching: find.byType(Scrollable),
                  )
                  .first,
            );
            await action(t, const Key('community-member-next-page'), source);
            expect(port.calls.last.$3, 20);
            await action(
              t,
              const Key('community-member-previous-page'),
              source,
            );
            expect(port.calls.last.$3, 0);
            expect(port.calls.last.$2, 'retained search');
            expect(
              port.calls.last.$4,
              source == 'pointer'
                  ? InteractionSource.pointer
                  : InteractionSource.keyboard,
            );
            expect(
              t.state(find.byType(CommunityWorkspaceView)),
              same(rowState),
            );
            // The entry is there for everyone (user 2026-10-31).
            expect(
              find.byKey(const ValueKey('community-section-manage')),
              findsOneWidget,
            );
            expect(t.takeException(), isNull);
            await t.pumpWidget(const SizedBox());
          } finally {
            semantics.dispose();
          }
        },
      );
      testWidgets(
        'existing workspace sections and manage back preserve original capabilities $suite $source',
        (t) async {
          final semantics = t.ensureSemantics(), port = ExampleCommunities();
          addTearDown(port.close);
          try {
            await mount(
              t,
              workspace(port, ref: exampleTarget),
              suite,
              width: 900,
            );
            final controller = t
                .state<CommunityWorkspaceViewState>(
                  find.byType(CommunityWorkspaceView),
                )
                .model;
            for (final section in ['chat', 'ships', 'members', 'manage']) {
              await action(t, ValueKey('community-section-$section'), source);
              if (section != 'manage') {
                expect(controller.selectedSection, section);
              }
            }
            await action(t, const ValueKey('community-settings-back'), source);
            expect(controller.selectedSection, 'members');
            expect(find.byType(CommunitySectionNavigation), findsOneWidget);
            expect(t.takeException(), isNull);
            await t.pumpWidget(const SizedBox());
          } finally {
            semantics.dispose();
          }
        },
      );
    }
    testWidgets(
      'workspace passive counters latest reversal reduced motion and unknowns $suite',
      (t) async {
        late StateSetter set;
        int? value = 1;
        final live = await mount(
          t,
          StatefulBuilder(
            builder: (_, s) {
              set = s;
              return StarBridgePassiveCount(
                value: value,
                valueKey: const Key('count'),
              );
            },
          ),
          suite,
        );
        for (final next in [2, 4, 3, 7]) {
          set(() => value = next);
          await t.pump(const Duration(milliseconds: 100));
        }
        if (suite == InteractionSuite.standard) {
          expect(find.byType(SuiteCounter), findsNothing);
          expect(find.text('7'), findsOneWidget);
        } else {
          final counter = t.widget<SuiteCounter>(
            find.byKey(const Key('count')),
          );
          expect(counter.value, 7);
          expect(counter.coalesceDataUpdates, true);
          expect(counter.source, InteractionSource.programmatic);
          live.change(() => live.reduce = true);
          await t.pump();
          await t.pump();
          expect(find.text('7'), findsOneWidget);
          expect(t.binding.transientCallbackCount, 0);
        }
        set(() => value = null);
        await t.pumpAndSettle();
        expect(find.text('—'), findsOneWidget);
        expect(find.byType(SuiteCounter), findsNothing);
        expect(find.text('0'), findsNothing);
        await t.pumpWidget(const SizedBox());
      },
    );
    testWidgets(
      'member input style and reduce change retain native controller and text $suite',
      (t) async {
        final port = Port();
        addTearDown(port.changes.close);
        final live = await mount(t, workspace(port), suite, width: 600);
        final field = find.byKey(const Key('community-member-search'));
        await t.enterText(field, 'unsent member query');
        final editor = t
            .widget<EditableText>(
              find.descendant(of: field, matching: find.byType(EditableText)),
            )
            .controller;
        final reads = port.calls.length;
        live.change(() {
          live.reduce = true;
          live.light = true;
          live.suite = suite == InteractionSuite.glow
              ? InteractionSuite.scan
              : InteractionSuite.glow;
        });
        await t.pump();
        await t.pump();
        expect(
          t
              .widget<EditableText>(
                find.descendant(of: field, matching: find.byType(EditableText)),
              )
              .controller,
          same(editor),
        );
        expect(editor.text, 'unsent member query');
        expect(port.calls.length, reads);
        await t.pumpWidget(const SizedBox());
      },
    );
    testWidgets(
      'compact unknown snapshot has three dashes and no fabricated counters $suite',
      (t) async {
        await mount(
          t,
          const CommunityCompactHeader(
            name: 'Unknown snapshot',
            code: 'ORG',
            logo: SizedBox(),
            narrow: false,
            showUnknownMetrics: true,
          ),
          suite,
          width: 600,
        );
        expect(find.text('—'), findsNWidgets(3));
        expect(find.byType(SuiteCounter), findsNothing);
        expect(find.text('0'), findsNothing);
        await t.pumpWidget(const SizedBox());
      },
    );
    for (final operation in ['details', 'leave', 'disband']) {
      testWidgets('workspace disposal retires owned $operation route $suite', (
        t,
      ) async {
        final port = ExampleCommunities();
        addTearDown(port.close);
        final live = await mount(
          t,
          workspace(port, ref: exampleTarget),
          suite,
          width: 900,
        );
        if (operation == 'details') {
          await action(t, const Key('community-open-details'), 'keyboard');
        } else {
          await action(
            t,
            const ValueKey('community-section-manage'),
            'keyboard',
          );
          await action(t, const ValueKey('settings-nav-danger'), 'keyboard');
          await action(
            t,
            ValueKey(
              operation == 'leave'
                  ? 'leave-with-successor'
                  : 'disband-community',
            ),
            'keyboard',
          );
        }
        live.change(() => live.visible = false);
        await settleCommunityImages(t);
        expect(dialog(), findsNothing);
        expect(find.byType(CommunityOwnershipExitDialog), findsNothing);
        expect(find.byType(CommunityDisbandDialog), findsNothing);
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
      });
    }
    testWidgets(
      'details live settings and account invalidation settle and remove $suite',
      (t) async {
        final port = Port();
        addTearDown(port.changes.close);
        final live = await mount(t, workspace(port), suite, width: 600);
        await action(
          t,
          const Key('community-open-details'),
          'pointer',
          settle: false,
        );
        live.change(() {
          live.reduce = true;
          live.light = true;
        });
        await t.pump();
        await t.pump();
        final route =
            ModalRoute.of(t.element(dialog()))! as StarBridgeDialogRoute;
        expect(route.animation!.value, 1);
        port.changes.add(null);
        await settleCommunityImages(t);
        expect(dialog(), findsNothing);
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
      },
    );
    testWidgets(
      'details refresh is guarded preserves search and actual input source $suite',
      (t) async {
        final port = Port();
        addTearDown(port.changes.close);
        await mount(t, workspace(port), suite, width: 600);
        await t.enterText(
          find.byKey(const Key('community-member-search')),
          'original query',
        );
        await action(
          t,
          const Key('community-member-search-submit'),
          'keyboard',
        );
        await action(t, const Key('community-open-details'), 'keyboard');
        await inside(t, const Key('community-details-refresh'), 'keyboard');
        expect(dialog(), findsNothing);
        expect(port.calls.last.$2, 'original query');
        expect(port.calls.last.$4, InteractionSource.keyboard);
        await t.pumpWidget(const SizedBox());
      },
    );
    testWidgets(
      'chat unsaved guard cancel keeps draft and explicit leave permits section $suite',
      (t) async {
        final port = ExampleCommunities();
        addTearDown(port.close);
        await mount(t, workspace(port, ref: exampleTarget), suite, width: 900);
        await action(t, const ValueKey('community-section-chat'), 'keyboard');
        final state = t.state<CommunityChatPanelState>(
          find.byType(CommunityChatPanel),
        );
        await t.enterText(
          find
              .descendant(
                of: find.byType(CommunityChatPanel),
                matching: find.byType(TextField),
              )
              .last,
          'Retained chat draft',
        );
        await action(
          t,
          const ValueKey('community-section-members'),
          'keyboard',
          settle: false,
        );
        await settleCommunityImages(t);
        expect(find.byType(AlertDialog), findsOneWidget);
        final cancel = find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('继续编辑'),
        );
        await t.tap(cancel);
        await settleCommunityImages(t);
        expect(
          t.state<CommunityChatPanelState>(find.byType(CommunityChatPanel)),
          same(state),
        );
        expect(find.text('Retained chat draft'), findsOneWidget);
        await action(
          t,
          const ValueKey('community-section-members'),
          'keyboard',
          settle: false,
        );
        await settleCommunityImages(t);
        await t.tap(
          find.descendant(
            of: find.byType(AlertDialog),
            matching: find.text('丢弃草稿并返回'),
          ),
        );
        await settleCommunityImages(t);
        expect(find.byType(CommunitySectionNavigation), findsOneWidget);
        expect(
          t
              .state<CommunityWorkspaceViewState>(
                find.byType(CommunityWorkspaceView),
              )
              .model
              .selectedSection,
          'members',
        );
        await t.pumpWidget(const SizedBox());
      },
    );
  }
  for (final suite in [InteractionSuite.scan, InteractionSuite.glow]) {
    testWidgets('workspace compact header actual number pixels review $suite', (
      t,
    ) async {
      final port = Port(), capture = GlobalKey();
      addTearDown(port.changes.close);
      await mount(t, workspace(port), suite, width: 600, capture: capture);
      final metrics = ['online', 'gaming', 'member']
          .map(
            (key) => t.getRect(
              find.byKey(ValueKey('community-presence-value-$key')),
            ),
          )
          .toList();
      final boundary =
          capture.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      await t.runAsync(() async {
        final image = await boundary.toImage();
        final png = await image.toByteData(format: ImageByteFormat.png);
        final raw = (await image.toByteData(format: ImageByteFormat.rawRgba))!
            .buffer
            .asUint8List();
        for (final rect in metrics) {
          var n = 0;
          for (var y = rect.top.ceil(); y < rect.bottom.floor(); y++) {
            for (var x = rect.left.ceil(); x < rect.right.floor(); x++) {
              final i = (y * image.width + x) * 4;
              if (raw[i + 1] > 110 && raw[i + 2] > 95 && raw[i + 3] > 240) n++;
            }
          }
          expect(n, greaterThan(3));
        }
        Directory('build/reviews/interaction-batch3ak')
            .createSync(recursive: true);
        File(
          'build/reviews/interaction-batch3ak/${suite.name}-compact-header.png',
        ).writeAsBytesSync(png!.buffer.asUint8List());
        image.dispose();
      });
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    });
  }
}
