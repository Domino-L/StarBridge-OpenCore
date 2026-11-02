import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_switch.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_action_button.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_dialog.dart';
import 'package:starbridge_flutter/features/settings/community_member_override.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/features/settings/community_member_visibility_dialog.dart';
import 'package:starbridge_flutter/features/settings/community_member_sharing.dart';
import 'package:starbridge_flutter/features/settings/community_sharing.dart';
import 'package:starbridge_flutter/features/settings/local_privacy_controller.dart';
import 'package:starbridge_flutter/features/settings/local_privacy_scope_sections.dart';

import '../../features/settings/community_member_visibility_test.dart'
    show MemberFixture, memberJson;
import '../../features/settings/community_sharing_test.dart'
    show target, membershipTime;
import 'interaction_batch3i_test.dart' show scopedApp;
import 'interaction_batch3bi_test.dart' show input;

class MemberPort extends MemberFixture {
  int reads = 0;
  Completer<CommunityMemberPage>? held;
  Object? failure;
  @override
  Future<CommunityMemberPage> readCommunityMembers(
    CommunitySharingScope scope, {
    int offset = 0,
    String? revision,
  }) async {
    reads++;
    if (failure case final error?) throw error;
    return held?.future ??
        super.readCommunityMembers(scope, offset: offset, revision: revision);
  }
}

class SelfPort extends MemberPort {
  @override
  Future<CommunityMemberPage> readCommunityMembers(
    CommunitySharingScope scope, {
    int offset = 0,
    String? revision,
  }) async {
    final page = await super.readCommunityMembers(
      scope,
      offset: offset,
      revision: revision,
    );
    return CommunityMemberPage.fromJson(
      {
        'schemaVersion': 3,
        'code': scope.code,
        'joinedAt': scope.joinedAt,
        'revision': page.revision,
        'offset': page.offset,
        'total': page.total,
        'members': [
          for (var i = offset; i < count && i < offset + 100; i++)
            {
              ...memberJson(i),
              'isSelf': i == 0,
              'defaultCanView': scope.allMembersCanView,
              'legacyGroupFields': legacyFields[i] ?? 0,
            },
        ],
      },
      scope,
      offset,
      revision,
    );
  }
}

MemberPort legacyPort() {
  final p = MemberPort()..legacyFields = {0: 3, 1: 2};
  p.settings = p.settings.copyWith(
    communities: [
      CommunitySharingScope(
        code: 'A',
        joinedAt: membershipTime,
        fields: 3,
        administratorsCanView: false,
        allMembersCanView: false,
        visibilityGroupIds: ['legacy'],
        memberOverrides: [
          CommunityMemberOverride(
            accountId: 'member-0',
            joinedAt: membershipTime,
            fields: 0,
          ),
        ],
      ),
    ],
  );
  return p;
}

Widget factory(LocalPrivacyController c, InteractionSuite suite) => scopedApp(
  Builder(
    builder: (context) => StarBridgeActionButton(
      controlKey: const Key('open-members'),
      child: const Text('open'),
      onActivate: (source) => unawaited(
        editCommunityMemberVisibility(
          context,
          c,
          target('A'),
          c.draft!.communities!.single,
          source: source,
        ),
      ),
    ),
  ),
  suite,
);

Future<void> action(WidgetTester t, String source, String id) async {
  await t.pump();
  await input(t, source, Key(id));
}

Future<void> panel(
  WidgetTester t,
  LocalPrivacyController c,
  InteractionSuite suite,
) async {
  await t.pumpWidget(
    scopedApp(
      CommunityMemberVisibilityDialog(
        controller: c,
        target: target('A'),
        scope: c.draft!.communities!.single,
      ),
      suite,
    ),
  );
  await t.pumpAndSettle();
}

Future<void> close(
  WidgetTester t,
  LocalPrivacyController c,
  MemberPort p,
) async {
  await t.pumpWidget(const SizedBox());
  await t.pump();
  c.dispose();
  await t.runAsync(p.close);
}

void main() {
  for (final suite in InteractionSuite.values) {
    for (final source in ['pointer', 'keyboard', 'reader']) {
      testWidgets(
        '$suite $source real organization section forwards member opening source',
        (t) async {
          final p = MemberPort(),
              c = LocalPrivacyController(p),
              semantics = t.ensureSemantics();
          try {
            await c.refresh();
            await t.pumpWidget(
              scopedApp(
                SingleChildScrollView(
                  child: LocalPrivacyOrganizationsSection(controller: c),
                ),
                suite,
              ),
            );
            await t.pumpAndSettle();
            await action(t, source, 'privacy-scope-A-members');
            await t.pumpAndSettle();
            final route = ModalRoute.of(
              t.element(find.byType(CommunityMemberVisibilityDialog)),
            ) as StarBridgeDialogRoute;
            expect(route.instant, source != 'pointer');
            expect(p.writes, 0);
            expect(p.applies, 0);
            await action(t, 'keyboard', 'privacy-member-cancel');
            await t.pumpAndSettle();
          } finally {
            await close(t, c, p);
            semantics.dispose();
          }
        },
      );
    }
    testWidgets(
      '$suite account invalidation still clears member data during a normal exit',
      (t) async {
        final p = MemberPort(), c = LocalPrivacyController(p);
        try {
          await c.refresh();
          await t.pumpWidget(factory(c, suite));
          await action(t, 'pointer', 'open-members');
          await t.pumpAndSettle();
          await action(t, 'pointer', 'privacy-member-confirm');
          p.events.add(null);
          await t.pump();
          await t.pump();
          expect(
            find.byKey(
              const Key('privacy-member-member-0-ship'),
              skipOffstage: false,
            ),
            findsNothing,
          );
          expect(p.writes, 0);
        } finally {
          await close(t, c, p);
        }
      },
    );
    testWidgets('$suite member controls use the approved suite', (t) async {
      final p = MemberPort();
      final owner = LocalPrivacyController(p);
      try {
        await owner.refresh();
        await panel(t, owner, suite);
        expect(find.byType(StarBridgeSwitch), findsAtLeastNWidgets(4));
      } finally {
        await close(t, owner, p);
      }
    });
    testWidgets(
      '$suite replacing member owner while reading loads the new directory',
      (t) async {
        final old = MemberPort(), next = MemberPort();
        final a = LocalPrivacyController(old), b = LocalPrivacyController(next);
        try {
          await a.refresh();
          await b.refresh();
          old.held = Completer<CommunityMemberPage>();
          await t.pumpWidget(
            scopedApp(
              CommunityMemberVisibilityDialog(
                controller: a,
                target: target('A'),
                scope: a.draft!.communities!.single,
              ),
              suite,
            ),
          );
          await t.pump();
          await panel(t, b, suite);
          expect(
            find.byKey(const Key('privacy-member-member-0-ship')),
            findsOneWidget,
          );
        } finally {
          await t.pumpWidget(const SizedBox());
          old.held!.completeError(StateError('synthetic cancelled'));
          await t.pump();
          a.dispose();
          b.dispose();
          await t.runAsync(() async {
            await old.close();
            await next.close();
          });
        }
      },
    );
    for (final source in ['pointer', 'keyboard', 'reader']) {
      testWidgets('$suite $source toggles/reset/cancel never writes privacy', (
        t,
      ) async {
        final p = MemberPort();
        final owner = LocalPrivacyController(p),
            semantics = t.ensureSemantics();
        try {
          await owner.refresh();
          await t.pumpWidget(factory(owner, suite));
          await action(t, source, 'open-members');
          await t.pumpAndSettle();
          final before = owner.draft;
          await action(t, source, 'privacy-member-member-0-ship');
          await t.pumpAndSettle();
          expect(owner.draft, same(before));
          expect(p.writes, 0);
          expect(p.applies, 0);
          await action(t, source, 'privacy-member-member-0-reset');
          await t.pumpAndSettle();
          final row = t
              .widgetList<StarBridgeSwitch>(find.byType(StarBridgeSwitch))
              .singleWhere(
                (w) =>
                    w.controlKey == const Key('privacy-member-member-0-ship'),
              );
          expect(row.value, isTrue);
          await action(t, source, 'privacy-member-cancel');
          await t.pumpAndSettle();
          expect(owner.draft, same(before));
          expect(p.writes, 0);
        } finally {
          await close(t, owner, p);
          semantics.dispose();
        }
      });
      testWidgets(
        '$suite $source confirming only stages changes; explicit parent save owns failures',
        (t) async {
          final p = MemberPort(),
              c = LocalPrivacyController(p),
              semantics = t.ensureSemantics();
          try {
            await c.refresh();
            await t.pumpWidget(factory(c, suite));
            await action(t, source, 'open-members');
            await t.pumpAndSettle();
            await action(t, source, 'privacy-member-member-0-ship');
            await t.pumpAndSettle();
            await action(t, source, 'privacy-member-confirm');
            await t.pumpAndSettle();
            expect(
              c.draft!.communities!.single.memberOverrides!.single.fields,
              13,
            );
            expect(p.settings.communities!.single.memberOverrides, isNull);
            expect(p.writes, 0);
            expect(p.applies, 0);
            expect(c.dirty, isTrue);
            final draft = c.draft;
            p.failSave = true;
            await c.save();
            await t.pump();
            expect(c.draft, same(draft));
            expect(c.dirty, isTrue);
            expect(p.writes, 0);
            p.failSave = false;
            await c.save();
            await t.pump();
            expect(p.writes, 1);
            expect(c.dirty, isFalse);
          } finally {
            await close(t, c, p);
            semantics.dispose();
          }
        },
      );
      for (final finish in ['pointer', 'keyboard', 'reader']) {
        testWidgets(
          '$suite $source conversion then $finish confirmation preserves explicit denials',
          (t) async {
            final p = legacyPort(),
                c = LocalPrivacyController(p),
                semantics = t.ensureSemantics();
            try {
              await c.refresh();
              await t.pumpWidget(factory(c, suite));
              await action(t, source, 'open-members');
              await t.pumpAndSettle();
              await action(t, source, 'privacy-member-convert');
              await t.pumpAndSettle();
              final route = ModalRoute.of(
                t.element(
                  find.byKey(const Key('privacy-member-convert-confirm')),
                ),
              ) as StarBridgeDialogRoute;
              expect(route.instant, source != 'pointer');
              await action(t, finish, 'privacy-member-convert-confirm');
              await t.pumpAndSettle();
              expect(c.draft!.communities!.single.visibilityGroupIds, [
                'legacy',
              ]);
              await action(t, finish, 'privacy-member-confirm');
              await t.pumpAndSettle();
              final result = c.draft!.communities!.single;
              expect(result.visibilityGroupIds, isEmpty);
              expect(
                result.memberOverrides!.map(
                  (r) => '${r.accountId}:${r.fields}',
                ),
                ['member-0:0', 'member-1:2'],
              );
              expect(result.allMembersCanView, isFalse);
              expect(p.writes, 0);
              expect(p.applies, 0);
            } finally {
              await close(t, c, p);
              semantics.dispose();
            }
          },
        );
      }
      testWidgets('$suite $source initial member wait follows input origin', (
        t,
      ) async {
        final p = MemberPort(),
            c = LocalPrivacyController(p),
            semantics = t.ensureSemantics();
        try {
          await c.refresh();
          p.held = Completer<CommunityMemberPage>();
          await t.pumpWidget(factory(c, suite));
          await action(t, source, 'open-members');
          expect(
            InteractionScope.of(t.element(find.byType(SuiteProgressBar)))
                .reduceMotion,
            source != 'pointer',
          );
          await action(t, 'keyboard', 'privacy-member-cancel');
          await t.pump();
          p.held!.completeError(StateError('synthetic cancelled'));
          await t.pump();
          await t.pumpAndSettle();
          expect(find.byType(CommunityMemberVisibilityDialog), findsNothing);
          expect(p.writes, 0);
        } finally {
          await close(t, c, p);
          semantics.dispose();
        }
      });
    }
    testWidgets(
      '$suite search reaches all pages without changing staged rules',
      (t) async {
        final p = MemberPort()..count = 205, c = LocalPrivacyController(p);
        try {
          await c.refresh();
          await panel(t, c, suite);
          await t.enterText(
            find.byKey(const Key('privacy-member-search')),
            'Member 204',
          );
          await t.pumpAndSettle();
          expect(
            find.byKey(const Key('privacy-member-member-204-ship')),
            findsOneWidget,
          );
          expect(p.offsets, [0, 100, 200]);
          expect(p.writes, 0);
        } finally {
          await close(t, c, p);
        }
      },
    );
    testWidgets(
      '$suite retry uses original five seconds; unsupported errors do not retry',
      (t) async {
        final p = MemberPort()..failure = StateError('synthetic private error'),
            c = LocalPrivacyController(p);
        try {
          await c.refresh();
          await panel(t, c, suite);
          expect(find.byType(StarBridgeSwitch), findsNothing);
          p.failure = null;
          await t.pump(const Duration(seconds: 5));
          await t.pumpAndSettle();
          expect(find.byType(StarBridgeSwitch), findsAtLeastNWidgets(4));
          expect(p.writes, 0);
        } finally {
          await close(t, c, p);
        }
      },
    );
    testWidgets(
      '$suite invalidation cancels only its conversion and preserves changed-state UI',
      (t) async {
        final p = legacyPort(), c = LocalPrivacyController(p);
        try {
          await c.refresh();
          await panel(t, c, suite);
          await action(t, 'pointer', 'privacy-member-convert');
          await t.pumpAndSettle();
          p.events.add(null);
          await t.pump();
          await t.pumpAndSettle();
          expect(
            find.byKey(const Key('privacy-member-convert-confirm')),
            findsNothing,
          );
          expect(find.byType(CommunityMemberVisibilityDialog), findsOneWidget);
          expect(find.byType(StarBridgeSwitch), findsNothing);
          expect(p.writes, 0);
        } finally {
          await close(t, c, p);
        }
      },
    );
    testWidgets(
      '$suite parent draft replacement cannot be overwritten by an older member edit',
      (t) async {
        final p = MemberPort(), c = LocalPrivacyController(p);
        try {
          await c.refresh();
          await t.pumpWidget(factory(c, suite));
          await action(t, 'pointer', 'open-members');
          await t.pumpAndSettle();
          await action(t, 'pointer', 'privacy-member-member-0-ship');
          await t.pumpAndSettle();
          c.editCommunity(target('A').choice(fields: 1));
          await t.pump();
          final confirm = t
              .widgetList<StarBridgeActionButton>(
                find.byType(StarBridgeActionButton),
              )
              .singleWhere(
                (w) => w.controlKey == const Key('privacy-member-confirm'),
              );
          expect(confirm.onActivate, isNull);
          expect(c.draft!.communities!.single.fields, 1);
          expect(p.writes, 0);
        } finally {
          await close(t, c, p);
        }
      },
    );
    testWidgets(
      '$suite conversion cancel or Escape leaves legacy grants untouched',
      (t) async {
        final p = legacyPort(), c = LocalPrivacyController(p);
        try {
          await c.refresh();
          await panel(t, c, suite);
          await action(t, 'pointer', 'privacy-member-convert');
          await t.pumpAndSettle();
          await t.sendKeyEvent(LogicalKeyboardKey.escape);
          await t.pump();
          await t.pump();
          expect(
            find.byKey(const Key('privacy-member-convert-confirm')),
            findsNothing,
          );
          expect(c.draft!.communities!.single.visibilityGroupIds, ['legacy']);
          expect(p.writes, 0);
        } finally {
          await close(t, c, p);
        }
      },
    );
    testWidgets(
      '$suite unsupported member directory never retries or grants fields',
      (t) async {
        final p = MemberPort()
              ..failure = const BridgeClientException(
                'host.capability_missing',
              ),
            c = LocalPrivacyController(p);
        try {
          await c.refresh();
          await panel(t, c, suite);
          expect(p.reads, 1);
          await t.pump(const Duration(seconds: 10));
          await t.pumpAndSettle();
          expect(p.reads, 1);
          expect(find.byType(StarBridgeSwitch), findsNothing);
          expect(p.writes, 0);
        } finally {
          await close(t, c, p);
        }
      },
    );
    testWidgets(
      '$suite self and parent field mask keep their controls disabled',
      (t) async {
        final p = SelfPort(), c = LocalPrivacyController(p);
        p.settings = p.settings.copyWith(
          communities: [target('A').choice(fields: 1)],
        );
        try {
          await c.refresh();
          await panel(t, c, suite);
          final controls = t.widgetList<StarBridgeSwitch>(
            find.byType(StarBridgeSwitch),
          );
          expect(
            controls
                .singleWhere(
                  (w) =>
                      w.controlKey ==
                      const Key('privacy-member-member-0-presence'),
                )
                .onChanged,
            isNull,
          );
          expect(
            controls
                .singleWhere(
                  (w) =>
                      w.controlKey == const Key('privacy-member-member-1-ship'),
                )
                .onChanged,
            isNull,
          );
          expect(
            controls
                .singleWhere(
                  (w) =>
                      w.controlKey ==
                      const Key('privacy-member-member-1-presence'),
                )
                .onChanged,
            isNotNull,
          );
          expect(p.writes, 0);
        } finally {
          await close(t, c, p);
        }
      },
    );
    testWidgets(
      '$suite override ceiling remains enforced without partial mutation',
      (t) async {
        final p = MemberPort(), c = LocalPrivacyController(p);
        p.settings = p.settings.copyWith(
          communities: [
            target('A')
                .choice(fields: 15)
                .copyWith(
                  memberOverrides: [
                    for (var i = 0; i < 1000; i++)
                      CommunityMemberOverride(
                        accountId: 'existing-$i',
                        joinedAt: membershipTime,
                        fields: 0,
                      ),
                  ],
                ),
          ],
        );
        try {
          await c.refresh();
          await panel(t, c, suite);
          await action(t, 'pointer', 'privacy-member-member-0-ship');
          await t.pumpAndSettle();
          final switchWidget = t
              .widgetList<StarBridgeSwitch>(find.byType(StarBridgeSwitch))
              .singleWhere(
                (w) =>
                    w.controlKey == const Key('privacy-member-member-0-ship'),
              );
          expect(switchWidget.value, isTrue);
          expect(p.writes, 0);
          expect(c.draft!.communities!.single.memberOverrides!.length, 1000);
        } finally {
          await close(t, c, p);
        }
      },
    );
    testWidgets(
      '$suite reduce and palette update do not erase local member edits or search',
      (t) async {
        final p = MemberPort(), c = LocalPrivacyController(p);
        try {
          await c.refresh();
          await panel(t, c, suite);
          final scope = c.draft!.communities!.single;
          await t.enterText(
            find.byKey(const Key('privacy-member-search')),
            'Member 0',
          );
          await t.pumpAndSettle();
          await action(t, 'pointer', 'privacy-member-member-0-ship');
          await t.pumpAndSettle();
          await t.pumpWidget(
            scopedApp(
              CommunityMemberVisibilityDialog(
                controller: c,
                target: target('A'),
                scope: scope,
              ),
              suite,
              reduce: true,
              light: true,
            ),
          );
          await t.pump();
          await t.pumpAndSettle();
          expect(
            t
                    .widget<TextField>(
                      find.byKey(const Key('privacy-member-search')),
                    )
                    .controller
                    ?.text ??
                t
                    .widget<EditableText>(find.byType(EditableText))
                    .controller
                    .text,
            'Member 0',
          );
          final toggle = t
              .widgetList<StarBridgeSwitch>(find.byType(StarBridgeSwitch))
              .singleWhere(
                (w) =>
                    w.controlKey == const Key('privacy-member-member-0-ship'),
              );
          expect(toggle.value, isFalse);
          expect(p.writes, 0);
        } finally {
          await close(t, c, p);
        }
      },
    );
    testWidgets(
      '$suite rapid active toggles retain the latest draft and never publish',
      (t) async {
        final p = MemberPort(), c = LocalPrivacyController(p);
        try {
          await c.refresh();
          await panel(t, c, suite);
          for (var i = 0; i < 5; i++) {
            await action(t, 'pointer', 'privacy-member-member-0-ship');
            await t.pump(const Duration(milliseconds: 70));
          }
          await t.pumpAndSettle();
          final toggle = t
              .widgetList<StarBridgeSwitch>(find.byType(StarBridgeSwitch))
              .singleWhere(
                (w) =>
                    w.controlKey == const Key('privacy-member-member-0-ship'),
              );
          expect(toggle.value, isFalse);
          expect(p.writes, 0);
          expect(p.applies, 0);
        } finally {
          await close(t, c, p);
        }
      },
    );
    testWidgets(
      '$suite late old-owner directory success cannot replace current members',
      (t) async {
        final old = MemberPort(),
            next = MemberPort(),
            a = LocalPrivacyController(old),
            b = LocalPrivacyController(next);
        try {
          await a.refresh();
          await b.refresh();
          final scope = a.draft!.communities!.single;
          old.held = Completer<CommunityMemberPage>();
          await t.pumpWidget(
            scopedApp(
              CommunityMemberVisibilityDialog(
                controller: a,
                target: target('A'),
                scope: scope,
              ),
              suite,
            ),
          );
          await t.pump();
          await panel(t, b, suite);
          old.held!.complete(
            CommunityMemberPage.fromJson(
              {
                'schemaVersion': 3,
                'code': scope.code,
                'joinedAt': scope.joinedAt,
                'revision': 'A' * 64,
                'offset': 0,
                'total': 0,
                'members': <Object>[],
              },
              scope,
              0,
              null,
            ),
          );
          await t.pump();
          await t.pumpAndSettle();
          expect(
            find.byKey(const Key('privacy-member-member-0-ship')),
            findsOneWidget,
          );
          expect(old.writes, 0);
          expect(next.writes, 0);
        } finally {
          await t.pumpWidget(const SizedBox());
          a.dispose();
          b.dispose();
          await t.runAsync(() async {
            await old.close();
            await next.close();
          });
        }
      },
    );
    testWidgets(
      '$suite successful pointer handoff keeps editor content during exit',
      (t) async {
        final p = MemberPort(), c = LocalPrivacyController(p);
        try {
          await c.refresh();
          await t.pumpWidget(factory(c, suite));
          await action(t, 'pointer', 'open-members');
          await t.pumpAndSettle();
          await action(t, 'pointer', 'privacy-member-member-0-ship');
          await t.pumpAndSettle();
          await action(t, 'pointer', 'privacy-member-confirm');
          await t.pump(const Duration(milliseconds: 20));
          expect(c.dirty, isTrue);
          expect(
            find.byKey(
              const Key('privacy-member-member-0-ship'),
              skipOffstage: false,
            ),
            findsOneWidget,
          );
          await t.pumpAndSettle();
          expect(p.writes, 0);
        } finally {
          await close(t, c, p);
        }
      },
    );
  }
}
