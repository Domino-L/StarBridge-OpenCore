import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show ImageByteFormat, SemanticsAction;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_select_form_field.dart';
import 'package:starbridge_flutter/features/communities/community_profile_dialog.dart';
import 'package:starbridge_flutter/features/communities/community_profile_port.dart';
import 'package:starbridge_flutter/features/communities/community_management_dialog.dart';
import 'package:starbridge_flutter/features/communities/community_admissions_port.dart';
import 'package:starbridge_flutter/features/communities/community_ship_report_editor.dart';
import 'package:starbridge_flutter/features/communities/community_ship_report_controller.dart';
import 'package:starbridge_flutter/features/communities/community_ship_report_port.dart';
import 'package:starbridge_flutter/features/communities/communities_module.dart';
import 'package:starbridge_flutter/features/communities/communities_page.dart';

import 'interaction_batch3i_test.dart' show scopedApp;
import 'interaction_batch3aa_test.dart' show open, select;
import '../../features/friends/social_layout_test.dart' show loadFonts, size;
import '../../features/communities/community_profile_dialog_test.dart'
    show EditorPort;
import '../../features/communities/community_management_dialog_test.dart'
    show ManagementTestPort;
import '../../features/communities/community_image_test_support.dart'
    show settleCommunityImages;

class Live extends StatefulWidget {
  const Live(
    this.child,
    this.suite, {
    this.locale = const Locale('zh', 'CN'),
    this.scale = 1,
    super.key,
  });
  final Widget child;
  final InteractionSuite suite;
  final Locale locale;
  final double scale;
  @override
  State<Live> createState() => LiveState();
}

class LiveState extends State<Live> {
  late var suite = widget.suite;
  bool reduce = false, light = false, visible = true;
  void change(VoidCallback action) => setState(action);
  @override
  Widget build(BuildContext context) => scopedApp(
    Builder(
      builder: (context) => Localizations.override(
        context: context,
        locale: widget.locale,
        child: MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(widget.scale)),
          child: visible ? widget.child : const Text('已离开'),
        ),
      ),
    ),
    suite,
    reduce: reduce,
    light: light,
  );
}

Future<LiveState> mount(
  WidgetTester t,
  Widget child,
  InteractionSuite suite, {
  Locale locale = const Locale('zh', 'CN'),
  double scale = 1,
  GlobalKey? capture,
}) async {
  size(t, const Size(1280, 1000));
  final key = GlobalKey<LiveState>();
  final app = Live(child, suite, locale: locale, scale: scale, key: key);
  await t.pumpWidget(
    capture == null ? app : RepaintBoundary(key: capture, child: app),
  );
  await settleCommunityImages(t);
  return key.currentState!;
}

Finder field<T>(String suffix) => find.byWidgetPredicate(
  (w) => w is StarBridgeSelectFormField<T> && w.key.toString().contains(suffix),
);

Future<void> choose<T>(
  WidgetTester t,
  Finder finder,
  T value,
  String source,
) async {
  final config = t.widget<StarBridgeSelectFormField<T>>(finder);
  await open(t, config.controlKey!, source);
  await t.pumpAndSettle();
  final row = find.byKey(ValueKey<Object>((config.identity, value)));
  await t.ensureVisible(row);
  await t.pumpAndSettle();
  if (source == 'reader') {
    final node = t.getSemantics(row);
    expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
    t.binding.renderViews.single.owner!.semanticsOwner!.performAction(
      node.id,
      SemanticsAction.tap,
    );
    await t.pump();
    await t.pump();
  } else {
    await select(t, config.identity, value as Object, source);
  }
  await t.pumpAndSettle();
}

class HeldProfile extends EditorPort {
  Completer<CommunityProfileOutcome>? held;
  @override
  Future<CommunityProfileOutcome> saveProfile(
    String requestId,
    String editRef,
    Map<String, Object?> values,
  ) {
    saves.add(jsonDecode(jsonEncode(values)) as Map<String, dynamic>);
    return held!.future;
  }
}

class ReportPort implements CommunityShipReportPort {
  final intents = <CommunityShipReportIntent>[];
  final hold = Completer<CommunityShipReportOutcome>();
  @override
  bool get shipReportAvailable => true;
  @override
  Future<CommunityShipReportOutcome> reportShipImage(
    CommunityShipReportIntent intent,
  ) {
    intents.add(intent);
    return hold.future;
  }

  @override
  Future<CommunityShipReportOutcome> checkShipReport(
    CommunityShipReportIntent intent,
  ) async => const CommunityShipReportOutcome('accepted');
}

class SortPort implements CommunitiesPort {
  final changes = StreamController<void>.broadcast(sync: true);
  final requests =
      <({String view, String query, String? after, String? filters})>[];
  final held = <Completer<CommunityDirectory>>[];
  bool hold = false;
  int writes = 0;
  @override
  Stream<void> get invalidations => changes.stream;
  @override
  Future<CommunityDirectory> read({
    required String view,
    required String query,
    String? after,
    String? filters,
  }) {
    requests.add((view: view, query: query, after: after, filters: filters));
    if (hold && view == 'discover') {
      final next = Completer<CommunityDirectory>();
      held.add(next);
      return next.future;
    }
    return Future.value(CommunityDirectory(view, query, const []));
  }

  @override
  Future<String> execute(String action, String targetRef) async {
    writes++;
    return 'rejected';
  }

  @override
  Future<void> close() async => changes.close();
}

void main() {
  setUpAll(loadFonts);
  for (final suite in InteractionSuite.values) {
    for (final source in ['pointer', 'keyboard', 'reader']) {
      testWidgets(
        'profile eight dictionary fields preserve SDK and domain $suite $source',
        (t) async {
          final semantics = t.ensureSemantics();
          try {
            final port = EditorPort()..profile['hasLogo'] = false;
            (port.profile['profile'] as Map)['timeZoneId'] = 'Legacy/Zone';
            addTearDown(port.changes.close);
            final key = GlobalKey<CommunityProfileDialogState>();
            final live = await mount(
              t,
              CommunityProfileDialog(
                key: key,
                port: port,
                targetRef: 'a' * 32,
                embedded: true,
              ),
              suite,
            );
            const values = {
              'recruitingTarget': '新手友好',
              'joinPolicy': 'Approval',
              'inviteCodeCreationPolicy': 'management',
              'fleetInvitationCardPolicy': 'commander',
              'publicMemberScaleMode': 'Approx',
              'publicShipScaleMode': 'TotalOnly',
              'timeZoneId': 'UTC',
              'activityCadence': '周末行动',
            };
            final states = <String, FormFieldState<String>>{};
            for (final e in values.entries) {
              final finder = field<String>('-${e.key}');
              states[e.key] = t.state<FormFieldState<String>>(finder);
              await choose(t, finder, e.value, source);
              expect(key.currentState!.model.fields[e.key], e.value);
              expect(
                t.state<FormFieldState<String>>(finder),
                same(states[e.key]),
              );
            }
            live.change(() {
              live.suite = InteractionSuite.glow;
              live.reduce = true;
              live.light = true;
            });
            await t.pumpAndSettle();
            for (final e in values.entries) {
              expect(key.currentState!.model.fields[e.key], e.value);
              expect(
                t.state<FormFieldState<String>>(field<String>('-${e.key}')),
                same(states[e.key]),
              );
            }
            expect(port.saves, isEmpty);
            expect(key.currentState!.model.dirty, isTrue);
            await key.currentState!.save();
            await t.pumpAndSettle();
            expect(port.saves, hasLength(1));
            for (final e in values.entries) {
              expect(port.saves.single[e.key], e.value);
            }
            expect(port.saves.single.containsKey('internalOnly'), isFalse);
            expect(t.takeException(), isNull);
            await t.pumpWidget(const SizedBox());
          } finally {
            semantics.dispose();
          }
        },
      );

      testWidgets(
        'invite parameters preserve confirmation pending and refusal $suite $source',
        (t) async {
          final semantics = t.ensureSemantics();
          try {
            final port = ManagementTestPort()
              ..hold = Completer<CommunityAdmissionOutcome>();
            addTearDown(port.changes.close);
            final key = GlobalKey<CommunityManagementDialogState>();
            await mount(
              t,
              CommunityManagementDialog(
                key: key,
                port: port,
                targetRef: 'a' * 32,
                name: 'Organization',
                initialSection: 'invites',
                embedded: true,
              ),
              suite,
            );
            final days = find.byWidgetPredicate(
              (w) =>
                  w is StarBridgeSelectFormField<int> &&
                  w.identity == 'community-invite-days',
            );
            final uses = find.byWidgetPredicate(
              (w) =>
                  w is StarBridgeSelectFormField<int> &&
                  w.identity == 'community-invite-uses',
            );
            await choose(t, days, 30, source);
            await choose(t, uses, 0, source);
            expect(port.intents, isEmpty);
            unawaited(
              key.currentState!.act(CommunityAdmissionAction.generateInvite),
            );
            await t.pumpAndSettle();
            expect(port.intents, isEmpty);
            await t.tap(find.byKey(const Key('management-confirm-cancel')));
            await t.pumpAndSettle();
            expect(port.intents, isEmpty);
            expect(key.currentState!.days, 30);
            unawaited(
              key.currentState!.act(CommunityAdmissionAction.generateInvite),
            );
            await t.pumpAndSettle();
            await t.tap(find.byKey(const Key('management-confirm-accept')));
            await t.pump();
            await t.pump(const Duration(milliseconds: 350));
            expect(port.intents, hasLength(1));
            expect(port.intents.single.expiresInDays, 30);
            expect(port.intents.single.maxUses, 0);
            expect(
              t.widget<StarBridgeSelectFormField<int>>(days).onChanged,
              isNull,
            );
            expect(
              t.widget<StarBridgeSelectFormField<int>>(uses).onChanged,
              isNull,
            );
            port.hold!.complete(
              const CommunityAdmissionOutcome('rejected', error: 'notAllowed'),
            );
            await t.pumpAndSettle();
            expect(key.currentState!.days, 30);
            expect(key.currentState!.uses, 0);
            expect(key.currentState!.model.outcome!.status, 'rejected');
            expect(port.intents, hasLength(1));
            await t.pumpWidget(const SizedBox());
          } finally {
            semantics.dispose();
          }
        },
      );

      testWidgets(
        'report reason retains refused draft without replay $suite $source',
        (t) async {
          final semantics = t.ensureSemantics();
          try {
            final port = ReportPort();
            final model = CommunityShipReportController(
              port,
              'a' * 32,
              'b' * 32,
              'c' * 64,
            );
            addTearDown(model.dispose);
            await mount(
              t,
              ListenableBuilder(
                listenable: model,
                builder: (_, _) => CommunityShipReportEditor(
                  model: model,
                  shipName: 'Ship',
                  confirmingClose: false,
                  onKeepEditing: () {},
                  onDiscard: () {},
                ),
              ),
              suite,
            );
            final finder = find.byKey(const ValueKey('ship-report-reason'));
            await choose(t, finder, 'privacy', source);
            await t.enterText(
              find.byKey(const ValueKey('ship-report-details')),
              ' original note ',
            );
            expect(port.intents, isEmpty);
            final pending = model.submit();
            await t.pump();
            await t.pump();
            expect(
              t.widget<StarBridgeSelectFormField<String>>(finder).onChanged,
              isNull,
            );
            expect(port.intents.single.reason, 'privacy');
            expect(port.intents.single.details, 'original note');
            port.hold.complete(
              const CommunityShipReportOutcome('rejected', error: 'notAllowed'),
            );
            await pending;
            await t.pumpAndSettle();
            expect(model.reason, 'privacy');
            expect(model.details, ' original note ');
            expect(model.dirty, isTrue);
            expect(model.editable, isTrue);
            expect(port.intents, hasLength(1));
            await t.pumpWidget(const SizedBox());
          } finally {
            semantics.dispose();
          }
        },
      );

      testWidgets(
        'directory sort preserves query filters and original read owner $suite $source',
        (t) async {
          final semantics = t.ensureSemantics();
          try {
            final port = SortPort();
            final model = CommunitiesModule(port);
            addTearDown(model.dispose);
            await model.refresh(
              newView: 'discover',
              newQuery: '探索',
              newFilters: jsonEncode({
                'sort': 'recommended',
                'language': 'English',
              }),
            );
            await mount(
              t,
              CommunitiesPage(module: model, createPort: () => port),
              suite,
            );
            final before = port.requests.length;
            final finder = find.byWidgetPredicate(
              (w) =>
                  w is StarBridgeSelectFormField<String> &&
                  w.controlKey ==
                      const ValueKey('community-directory-sort-control'),
            );
            await choose(t, finder, 'members', source);
            expect(port.requests.length, before + 1);
            final request = port.requests.last;
            expect(request.view, 'discover');
            expect(request.query, '探索');
            expect(request.after, isNull);
            expect(jsonDecode(request.filters!), {
              'sort': 'members',
              'language': 'English',
            });
            expect(port.writes, 0);
            expect(t.takeException(), isNull);
            await t.pumpWidget(const SizedBox());
          } finally {
            semantics.dispose();
          }
        },
      );
    }

    for (final locale in [const Locale('zh', 'CN'), const Locale('en', 'US')]) {
      testWidgets(
        'profile clock and contacts remain flat domain values $suite $locale',
        (t) async {
          final port = EditorPort()..profile['hasLogo'] = false;
          addTearDown(port.changes.close);
          final key = GlobalKey<CommunityProfileDialogState>();
          final live = await mount(
            t,
            CommunityProfileDialog(
              key: key,
              port: port,
              targetRef: 'a' * 32,
              embedded: true,
            ),
            suite,
            locale: locale,
          );
          final state = key.currentState!;
          final twelve = locale.languageCode == 'en';
          // The shared clock lists: hours 0–23 (12-hour locales label them
          // "11 PM"), minutes by the quarter hour.
          await choose(t, field<int>('-0-start-hour'), 23, 'keyboard');
          await choose(t, field<int>('-0-start-minute'), 45, 'keyboard');
          await choose(t, field<int>('-0-end-hour'), 2, 'keyboard');
          await choose(t, field<int>('-0-end-minute'), 15, 'keyboard');
          expect(find.text(twelve ? '11 PM' : '23'), findsWidgets);
          await choose(t, field<String>('-0-platform'), 'Telegram', 'keyboard');
          final windows = state.model.fields['activityWindows'] as List;
          expect(windows.single['startTime'], '23:45');
          expect(windows.single['endTime'], '02:15');
          expect(windows.single['days'], ['fri']);
          expect(windows.single['endsNextDay'], isTrue);
          expect((state.model.fields['externalContacts'] as List).single, {
            'platform': 'Telegram',
            'value': 'private-contact',
          });
          final before = jsonEncode(state.model.changes);
          live.change(() {
            live.reduce = true;
            live.light = true;
            live.suite = InteractionSuite.rail;
          });
          await t.pumpAndSettle();
          expect(jsonEncode(state.model.changes), before);
          expect(port.saves, isEmpty);
          await state.save();
          await t.pumpAndSettle();
          expect(port.saves.single['activityWindows'], windows);
          expect(
            port.saves.single['externalContacts'],
            state.model.profile!.fields['externalContacts'],
          );
          expect(t.takeException(), isNull);
          await t.pumpWidget(const SizedBox());
        },
      );
    }

    testWidgets(
      'profile read-only access hides unavailable select chapters $suite',
      (t) async {
        final port = EditorPort()..profile['hasLogo'] = false;
        port.profile['access'] = {
          'canEditProfile': false,
          'canEditLogo': true,
          'canEditBanner': false,
        };
        addTearDown(port.changes.close);
        final key = GlobalKey<CommunityProfileDialogState>();
        await mount(
          t,
          CommunityProfileDialog(
            key: key,
            port: port,
            targetRef: 'a' * 32,
            embedded: true,
          ),
          suite,
        );
        final fields = t
            .widgetList<StarBridgeSelectFormField<String>>(
              find.byWidgetPredicate(
                (w) => w is StarBridgeSelectFormField<String>,
              ),
            )
            .toList();
        expect(fields, isEmpty);
        expect(key.currentState!.model.profile!.canEditProfile, isFalse);
        expect(key.currentState!.model.canSave, isFalse);
        expect(key.currentState!.model.dirty, isFalse);
        expect(port.saves, isEmpty);
        await t.pumpWidget(const SizedBox());
      },
    );

    testWidgets(
      'recruiting locks invitation-only item without losing draft $suite',
      (t) async {
        final port = EditorPort()..profile['hasLogo'] = false;
        addTearDown(port.changes.close);
        final key = GlobalKey<CommunityProfileDialogState>();
        await mount(
          t,
          CommunityProfileDialog(
            key: key,
            port: port,
            targetRef: 'a' * 32,
            embedded: true,
          ),
          suite,
        );
        final state = key.currentState!;
        state.update('recruitingEnabled', true);
        await t.pumpAndSettle();
        final finder = field<String>('-joinPolicy');
        final config = t.widget<StarBridgeSelectFormField<String>>(finder);
        expect(
          config.items!.singleWhere((e) => e.value == 'Invite').enabled,
          isFalse,
        );
        final before = jsonEncode(state.model.changes);
        await open(t, config.controlKey!, 'keyboard');
        await t.pumpAndSettle();
        await t.tap(
          find.byKey(ValueKey<Object>((config.identity, 'Invite'))),
          warnIfMissed: false,
        );
        await t.pumpAndSettle();
        expect(jsonEncode(state.model.changes), before);
        expect(port.saves, isEmpty);
        await t.sendKeyEvent(LogicalKeyboardKey.escape);
        await t.pumpAndSettle();
        await choose(t, finder, 'Approval', 'keyboard');
        expect(state.model.fields['joinPolicy'], 'Approval');
        await t.pumpWidget(const SizedBox());
      },
    );

    testWidgets(
      'structural profile removal retires open menu and old row $suite',
      (t) async {
        final port = EditorPort()..profile['hasLogo'] = false;
        addTearDown(port.changes.close);
        final key = GlobalKey<CommunityProfileDialogState>();
        await mount(
          t,
          CommunityProfileDialog(
            key: key,
            port: port,
            targetRef: 'a' * 32,
            embedded: true,
          ),
          suite,
        );
        final state = key.currentState!;
        final clock = t.widget<StarBridgeSelectFormField<int>>(
          field<int>('-0-start-minute'),
        );
        await open(t, clock.controlKey!, 'pointer');
        await t.pumpAndSettle();
        state.serial++;
        state.update('activityWindows', <Map<String, Object?>>[]);
        await t.pump();
        await t.pump();
        await t.pumpAndSettle();
        expect(
          find.byKey(ValueKey<Object>((clock.identity, 15))),
          findsNothing,
        );
        expect(state.model.fields['activityWindows'], isEmpty);
        expect(port.saves, isEmpty);
        expect(t.takeException(), isNull);
        for (final e in [('externalContacts', '-0-platform', 'Telegram')]) {
          final config = t.widget<StarBridgeSelectFormField<String>>(
            field<String>(e.$2),
          );
          await open(t, config.controlKey!, 'pointer');
          await t.pumpAndSettle();
          state.serial++;
          state.update(e.$1, <Map<String, Object?>>[]);
          await t.pump();
          await t.pump();
          await t.pumpAndSettle();
          expect(
            find.byKey(ValueKey<Object>((config.identity, e.$3))),
            findsNothing,
          );
          expect(state.model.fields[e.$1], isEmpty);
          expect(port.saves, isEmpty);
          expect(t.takeException(), isNull);
        }
        await t.pumpWidget(const SizedBox());
      },
    );

    for (final status in ['accepted', 'rejected']) {
      testWidgets(
        'late report response after departure cannot revive editor $suite $status',
        (t) async {
          final port = ReportPort();
          final model = CommunityShipReportController(
            port,
            'a' * 32,
            'b' * 32,
            'c' * 64,
          );
          bool disposed = false;
          addTearDown(() {
            if (!disposed) model.dispose();
          });
          final live = await mount(
            t,
            ListenableBuilder(
              listenable: model,
              builder: (_, _) => CommunityShipReportEditor(
                model: model,
                shipName: 'Ship',
                confirmingClose: false,
                onKeepEditing: () {},
                onDiscard: () {},
              ),
            ),
            suite,
          );
          await choose(
            t,
            find.byKey(const ValueKey('ship-report-reason')),
            'spam',
            'keyboard',
          );
          final pending = model.submit();
          await t.pump();
          await t.pump();
          live.change(() => live.visible = false);
          await t.pump();
          await t.pump();
          model.dispose();
          disposed = true;
          port.hold.complete(
            CommunityShipReportOutcome(
              status,
              error: status == 'rejected' ? 'notAllowed' : null,
            ),
          );
          await pending;
          await t.pumpAndSettle();
          expect(model.outcome, isNull);
          expect(model.reason, isNull);
          expect(model.details, isEmpty);
          expect(find.byType(CommunityShipReportEditor), findsNothing);
          expect(port.intents, hasLength(1));
          expect(t.takeException(), isNull);
          await t.pumpWidget(const SizedBox());
        },
      );
    }

    testWidgets('profile pending refusal and permission gates $suite', (
      t,
    ) async {
      final port = HeldProfile()
        ..profile['hasLogo'] = false
        ..held = Completer<CommunityProfileOutcome>();
      addTearDown(port.changes.close);
      final key = GlobalKey<CommunityProfileDialogState>();
      await mount(
        t,
        CommunityProfileDialog(
          key: key,
          port: port,
          targetRef: 'a' * 32,
          embedded: true,
        ),
        suite,
      );
      final finder = field<String>('-joinPolicy');
      await choose(t, finder, 'Approval', 'keyboard');
      final state = key.currentState!;
      final saving = state.save();
      await t.pump();
      await t.pump();
      expect(port.saves, hasLength(1));
      final fields = find.byWidgetPredicate(
        (w) => w is StarBridgeSelectFormField<String>,
      );
      for (final w in t.widgetList<StarBridgeSelectFormField<String>>(fields)) {
        expect(w.onChanged, isNull);
      }
      port.held!.complete(
        const CommunityProfileOutcome('rejected', error: 'dataInvalid'),
      );
      await saving;
      await t.pumpAndSettle();
      expect(state.model.fields['joinPolicy'], 'Approval');
      expect(state.model.dirty, isTrue);
      expect(port.saves, hasLength(1));
      port.profile['access'] = {
        'canEditProfile': false,
        'canEditLogo': true,
        'canEditBanner': false,
      };
      state.model.invalidate('notAllowed');
      await t.pumpAndSettle();
      for (final w in t.widgetList<StarBridgeSelectFormField<String>>(fields)) {
        expect(w.onChanged, isNull);
      }
      expect(port.saves, hasLength(1));
      await t.pumpWidget(const SizedBox());
    });

    testWidgets(
      'directory overlapping reads reject stale result and departure $suite',
      (t) async {
        final port = SortPort();
        final model = CommunitiesModule(port);
        addTearDown(model.dispose);
        await model.refresh(newView: 'discover', newQuery: '探索');
        final live = await mount(
          t,
          CommunitiesPage(module: model, createPort: () => port),
          suite,
        );
        port.hold = true;
        final finder = find.byWidgetPredicate(
          (w) =>
              w is StarBridgeSelectFormField<String> &&
              w.controlKey ==
                  const ValueKey('community-directory-sort-control'),
        );
        // Sorting is not a save. The original query owner accepts distinct requests
        // while reads are pending; the field is only disabled during a business write.
        await open(
          t,
          const ValueKey('community-directory-sort-control'),
          'keyboard',
        );
        await select(
          t,
          ('community-directory-sort', null),
          'members',
          'keyboard',
        );
        await t.pump(const Duration(milliseconds: 300));
        final config = t.widget<StarBridgeSelectFormField<String>>(finder);
        final trigger = find.byKey(config.controlKey!);
        t.widget<SuitePressable>(trigger).focusNode!.requestFocus();
        await t.pump();
        await t.pump();
        await t.sendKeyEvent(LogicalKeyboardKey.enter);
        await t.pump();
        await t.pump();
        final target = find.byKey(ValueKey<Object>((config.identity, 'name')));
        final item = t.widget(target);
        final focus = item is SuitePressable
            ? item.focusNode!
            : (item as MenuItemButton).focusNode!;
        focus.requestFocus();
        await t.pump();
        await t.pump();
        await t.sendKeyEvent(LogicalKeyboardKey.enter);
        await t.pump();
        await t.pump();
        await t.pump(const Duration(milliseconds: 300));
        expect(port.held, hasLength(2));
        port.held.last.completeError(const CommunityFailure('unavailable'));
        await t.pump();
        await t.pump();
        port.held.first.complete(
          const CommunityDirectory('discover', 'old', [
            CommunityCard(targetRef: 'old', name: 'stale'),
          ]),
        );
        await t.pumpAndSettle();
        expect(model.error, 'unavailable');
        expect(model.directory, isNull);
        expect(jsonDecode(model.filters!)['sort'], 'name');
        expect(model.query, '探索');
        expect(port.writes, 0);
        live.change(() => live.visible = false);
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
      },
    );

    testWidgets('report unknown and close confirmation lock selection $suite', (
      t,
    ) async {
      final port = ReportPort();
      final model = CommunityShipReportController(
        port,
        'a' * 32,
        'b' * 32,
        'c' * 64,
      );
      addTearDown(model.dispose);
      await mount(
        t,
        ListenableBuilder(
          listenable: model,
          builder: (_, _) => CommunityShipReportEditor(
            model: model,
            shipName: 'Ship',
            confirmingClose: true,
            onKeepEditing: () {},
            onDiscard: () {},
          ),
        ),
        suite,
      );
      final finder = find.byKey(const ValueKey('ship-report-reason'));
      expect(
        t.widget<StarBridgeSelectFormField<String>>(finder).onChanged,
        isNull,
      );
      model.edit('spam', 'note');
      final pending = model.submit();
      await t.pump();
      port.hold.complete(
        const CommunityShipReportOutcome('unknown', error: 'outcomeUnknown'),
      );
      await pending;
      await t.pumpAndSettle();
      expect(
        t.widget<StarBridgeSelectFormField<String>>(finder).onChanged,
        isNull,
      );
      expect(model.reason, 'spam');
      expect(model.details, 'note');
      expect(port.intents, hasLength(1));
      await t.pumpWidget(const SizedBox());
    });
  }

  for (final suite in [InteractionSuite.scan, InteractionSuite.glow]) {
    testWidgets('review invitation form at 200 percent $suite', (t) async {
      final port = ManagementTestPort();
      addTearDown(port.changes.close);
      final capture = GlobalKey();
      await mount(
        t,
        CommunityManagementDialog(
          port: port,
          targetRef: 'a' * 32,
          name: 'Organization',
          initialSection: 'invites',
          embedded: true,
        ),
        suite,
        scale: 2,
        capture: capture,
      );
      await open(t, const ValueKey('community-invite-uses-control'), 'pointer');
      await t.pumpAndSettle();
      await t.pump(const Duration(milliseconds: 500));
      final rectangles = [
        for (final value in [1, 5, 10, 0])
          t.getRect(
            find.byKey(ValueKey<Object>(('community-invite-uses', value))),
          ),
      ];
      for (var i = 1; i < rectangles.length; i++) {
        expect(
          rectangles[i].top,
          greaterThanOrEqualTo(rectangles[i - 1].bottom),
        );
      }
      // Capture the root to include the SDK overlay, not just the page boundary.
      final root = t.binding.renderViews.single;
      expect(root.size.width, 1280);
      final boundary =
          capture.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      await t.runAsync(() async {
        final image = await boundary.toImage();
        final data = await image.toByteData(format: ImageByteFormat.png);
        final raw = (await image.toByteData(format: ImageByteFormat.rawRgba))!;
        final bytes = raw.buffer.asUint8List();
        final textPixels = <int>[];
        for (final rect in rectangles) {
          var count = 0;
          for (var y = rect.top.ceil() + 4; y < rect.bottom.floor() - 4; y++) {
            for (
              var x = rect.left.ceil() + 10;
              x < rect.right.floor() - 10;
              x++
            ) {
              final n = (y * image.width + x) * 4;
              if (bytes[n] >= 125 &&
                  bytes[n] <= 175 &&
                  bytes[n + 1] >= 145 &&
                  bytes[n + 1] <= 190 &&
                  bytes[n + 2] >= 150 &&
                  bytes[n + 2] <= 200 &&
                  bytes[n + 3] >= 240) {
                count++;
              }
            }
          }
          textPixels.add(count);
        }
        expect(
          textPixels,
          everyElement(greaterThan(5)),
          reason: 'Each menu row must contain painted foreground text, not just a semantics/layout node.',
        );
        Directory('build/reviews/interaction-batch3ac')
            .createSync(recursive: true);
        File(
          'build/reviews/interaction-batch3ac/${suite.name}-invite-200-final.png',
        ).writeAsBytesSync(data!.buffer.asUint8List());
        File('build/reviews/interaction-batch3ac/${suite.name}-row-bounds.txt')
            .writeAsStringSync(rectangles.join('\n'));
        File('build/reviews/interaction-batch3ac/${suite.name}-row-text.txt')
            .writeAsStringSync(
              [
                for (final value in [1, 5, 10, 0])
                  t
                      .widget<RichText>(
                        find.descendant(
                          of: find.byKey(
                            ValueKey<Object>(('community-invite-uses', value)),
                          ),
                          matching: find.byType(RichText),
                        ),
                      )
                      .text
                      .toStringDeep(),
              ].join('\n'),
            );
        image.dispose();
      });
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    });
  }
}
