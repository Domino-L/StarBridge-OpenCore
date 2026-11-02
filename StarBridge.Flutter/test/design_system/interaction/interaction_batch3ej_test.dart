import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import 'package:starbridge_flutter/design_system/interaction/starbridge_dialog.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_switch.dart';
import 'package:starbridge_flutter/features/gameplay_time/gameplay_time_panel.dart';
import 'package:starbridge_flutter/features/settings/community_member_visibility_dialog.dart';
import 'package:starbridge_flutter/features/settings/local_privacy_controller.dart';

import '../../features/gameplay_time/gameplay_time_test.dart' show Harness;
import 'interaction_batch3bi_test.dart' as consent show showPanel, close;
import 'interaction_batch3bm_test.dart'
    as members
    show MemberPort, factory, close;
import 'interaction_batch3do_test.dart' show loadFonts, size;

Future<void> _twoFrames(WidgetTester t) async {
  await t.pump();
  await t.pump();
}

FocusNode _switchOwner(WidgetTester t, Finder row) {
  expect(row, findsOneWidget);
  final pressable = find.descendant(
    of: row,
    matching: find.byType(SuitePressable),
  );
  expect(pressable, findsOneWidget);
  final focus = t.widget<SuitePressable>(pressable).focusNode!;
  expect(focus.canRequestFocus, isTrue);
  return focus;
}

FocusNode _buttonOwner(WidgetTester t, String id) {
  final target = find.byKey(Key(id));
  expect(target, findsOneWidget);
  final widget = t.widget(target);
  if (widget is SuitePressable) {
    return widget.focusNode!;
  }
  expect(widget, isA<ButtonStyleButton>());
  return (widget as ButtonStyleButton).focusNode!;
}

/// Observe only public focus ownership. Every focus move is a genuine Tab;
/// these tests never substitute requestFocus, UI callbacks or controller edits.
Future<void> _tabActivate(
  WidgetTester t,
  FocusNode owner,
  LogicalKeyboardKey activation,
) async {
  expect(owner.canRequestFocus, isTrue);
  var tabs = 0;
  do {
    await t.sendKeyEvent(LogicalKeyboardKey.tab);
    await _twoFrames(t);
    tabs++;
  } while (!owner.hasPrimaryFocus && tabs < 48);
  expect(tabs, inInclusiveRange(1, 48));
  expect(FocusManager.instance.primaryFocus, same(owner));
  await t.sendKeyEvent(activation);
  await _twoFrames(t);
}

Finder _consentRow() => find.ancestor(
  of: find.byKey(const Key('gameplay-time-record-switch')),
  matching: find.byType(StarBridgeSwitch),
);

void main() {
  setUpAll(loadFonts);
  for (final suite in InteractionSuite.values) {
    testWidgets(
      '$suite real Tab Space consent holds the original account receipt and later pointer retains local motion permission',
      (t) async {
        size(t, const Size(1000, 850));
        final h = Harness();
        final semantics = t.ensureSemantics();
        try {
          await consent.showPanel(t, h, suite);
          final panel = find.byType(GameplayTimePanel);
          expect(panel, findsOneWidget);
          expect(
            t.widget<GameplayTimePanel>(panel).controller,
            same(h.controller),
          );
          final before = h.controller.value;
          expect(before.visible, isTrue);
          expect(before.busy, isFalse);
          expect(before.consent, 'allowed');
          expect(before.error, isNull);
          final row = _consentRow();
          expect(row, findsOneWidget);
          expect(t.widget<StarBridgeSwitch>(row).onChanged, isNotNull);
          expect(t.widget<StarBridgeSwitch>(row).value, isTrue);
          expect(
            h.requests.where((r) => r.name == 'gameplayTime.setConsent'),
            isEmpty,
          );

          h.holdNames.add('gameplayTime.setConsent');
          await _tabActivate(t, _switchOwner(t, row), LogicalKeyboardKey.space);
          final request = h.requests
              .where((r) => r.name == 'gameplayTime.setConsent')
              .single;
          expect(h.held, same(request));
          expect(request.payload, {'schemaVersion': 1, 'allowed': false});
          expect(request.sessionGeneration, 1);
          expect(request.accountContext!.environment, 'test');
          expect(request.accountContext!.authority, 'scm');
          expect(request.accountContext!.subject, 'synthetic-a');
          expect(h.controller.value.busy, isTrue);
          expect(h.controller.value.consent, 'allowed');
          expect(h.consent, 'allowed');
          expect(t.widget<StarBridgeSwitch>(row).value, isTrue);
          expect(t.widget<StarBridgeSwitch>(row).onChanged, isNull);
          final progress = find.byType(SuiteProgressBar);
          expect(progress, findsOneWidget);
          final keyboardWait = InteractionScope.of(t.element(progress));
          expect(keyboardWait.suite, suite);
          expect(keyboardWait.reduceMotion, isTrue);
          expect(keyboardWait.animates, isFalse);
          await t.pump(const Duration(milliseconds: 300));
          expect(h.held, same(request));
          expect(h.controller.value.busy, isTrue);
          expect(h.controller.value.consent, 'allowed');
          expect(h.consent, 'allowed');
          expect(
            h.requests.where((r) => r.name == 'gameplayTime.setConsent'),
            hasLength(1),
          );

          // Only this original held account response may confirm the change.
          h.holdNames.clear();
          h.respond(request);
          await _twoFrames(t);
          await t.pumpAndSettle();
          expect(h.controller.value.busy, isFalse);
          expect(h.controller.value.consent, 'declined');
          expect(h.consent, 'declined');
          expect(t.widget<StarBridgeSwitch>(row).value, isFalse);
          expect(t.widget<StarBridgeSwitch>(row).onChanged, isNotNull);
          expect(
            h.requests.where((r) => r.name == 'gameplayTime.setConsent'),
            hasLength(1),
          );

          // A new real pointer request must not inherit the old keyboard
          // policy. This asserts source policy, not visible pixel animation.
          h.holdNames.add('gameplayTime.setConsent');
          await t.ensureVisible(row);
          await t.pump();
          await t.tapAt(t.getCenter(row));
          await _twoFrames(t);
          final requests = h.requests
              .where((r) => r.name == 'gameplayTime.setConsent')
              .toList();
          expect(requests, hasLength(2));
          final pointerRequest = requests.last;
          expect(pointerRequest, isNot(same(request)));
          expect(h.held, same(pointerRequest));
          expect(pointerRequest.payload, {'schemaVersion': 1, 'allowed': true});
          expect(pointerRequest.sessionGeneration, request.sessionGeneration);
          expect(
            pointerRequest.accountContext!.toJson(),
            request.accountContext!.toJson(),
          );
          expect(h.controller.value.busy, isTrue);
          expect(h.controller.value.consent, 'declined');
          expect(h.consent, 'declined');
          expect(t.widget<StarBridgeSwitch>(row).onChanged, isNull);
          expect(t.widget<StarBridgeSwitch>(row).value, isFalse);
          expect(progress, findsOneWidget);
          final pointerWait = InteractionScope.of(t.element(progress));
          expect(pointerWait.suite, suite);
          expect(pointerWait.reduceMotion, isFalse);
          expect(pointerWait.animates, isTrue);
          expect(TickerMode.valuesOf(t.element(progress)).enabled, isTrue);
          await t.pump(const Duration(milliseconds: 300));
          expect(h.held, same(pointerRequest));
          expect(h.controller.value.busy, isTrue);
          expect(h.controller.value.consent, 'declined');
          expect(h.consent, 'declined');
          expect(
            h.requests.where((r) => r.name == 'gameplayTime.setConsent'),
            hasLength(2),
          );

          h.holdNames.clear();
          h.respond(pointerRequest);
          await _twoFrames(t);
          await t.pumpAndSettle();
          expect(h.controller.value.busy, isFalse);
          expect(h.controller.value.consent, 'allowed');
          expect(h.consent, 'allowed');
          expect(
            h.requests.where((r) => r.name == 'gameplayTime.setConsent'),
            hasLength(2),
          );
          expect(
            t.widget<GameplayTimePanel>(panel).controller,
            same(h.controller),
          );
          expect(t.takeException(), isNull);
        } finally {
          await consent.close(t, h);
          semantics.dispose();
        }
      },
      timeout: const Timeout(Duration(seconds: 45)),
    );

    testWidgets(
      '$suite real Tab member opening private edit and confirmation stage exact override before explicit parent save retry',
      (t) async {
        size(t, const Size(1000, 850));
        final p = members.MemberPort();
        final c = LocalPrivacyController(p);
        final semantics = t.ensureSemantics();
        try {
          await c.refresh();
          expect(c.canEdit, isTrue);
          expect(c.dirty, isFalse);
          final before = c.draft!;
          final saved = p.settings;
          final epoch = c.scopeEpoch;
          final revision = c.revision;
          final scope = before.communities!.single;
          expect(scope.memberOverrides, isNull);

          await t.pumpWidget(members.factory(c, suite));
          await t.pumpAndSettle();
          await _tabActivate(
            t,
            _buttonOwner(t, 'open-members'),
            LogicalKeyboardKey.enter,
          );
          await t.pumpAndSettle();
          final dialog = find.byType(CommunityMemberVisibilityDialog);
          expect(dialog, findsOneWidget);
          final widget = t.widget<CommunityMemberVisibilityDialog>(dialog);
          expect(widget.controller, same(c));
          expect(widget.scope, same(scope));
          expect(widget.target.code, scope.code);
          expect(widget.target.joinedAt, scope.joinedAt);
          expect(
            (ModalRoute.of(t.element(dialog))! as StarBridgeDialogRoute)
                .instant,
            isTrue,
          );
          expect(p.reads, 1);
          expect(c.scopeEpoch, epoch);
          expect(c.revision, revision);
          expect(c.draft, same(before));
          expect(p.settings, same(saved));
          expect(p.writes, 0);
          expect(p.applies, 0);

          final raw = find.byKey(const Key('privacy-member-member-0-ship'));
          final row = find.ancestor(
            of: raw,
            matching: find.byType(StarBridgeSwitch),
          );
          expect(row, findsOneWidget);
          expect(t.widget<StarBridgeSwitch>(row).value, isTrue);
          expect(t.widget<StarBridgeSwitch>(row).onChanged, isNotNull);
          await _tabActivate(t, _switchOwner(t, row), LogicalKeyboardKey.space);
          expect(t.widget<StarBridgeSwitch>(row).value, isFalse);
          expect(c.draft, same(before));
          expect(c.dirty, isFalse);
          expect(c.scopeEpoch, epoch);
          expect(c.revision, revision);
          expect(p.settings, same(saved));
          expect(p.revision, revision);
          expect(p.writes, 0);
          expect(p.applies, 0);
          if (suite == InteractionSuite.standard) {
            expect(TickerMode.valuesOf(t.element(raw)).enabled, isFalse);
          } else {
            expect(
              t.widget<SuiteSwitch>(raw).changeSource,
              InteractionSource.keyboard,
            );
          }

          await _tabActivate(
            t,
            _buttonOwner(t, 'privacy-member-confirm'),
            LogicalKeyboardKey.enter,
          );
          await t.pumpAndSettle();
          expect(dialog, findsNothing);
          expect(c.scopeEpoch, epoch);
          expect(c.revision, revision);
          final staged = c.draft!;
          final result = staged.communities!.single;
          expect(result.code, scope.code);
          expect(result.joinedAt, scope.joinedAt);
          final override = result.memberOverrides!.single;
          expect(override.accountId, 'member-0');
          expect(override.joinedAt, scope.joinedAt);
          expect(override.fields, 13);
          expect(
            result.toJson(),
            scope.copyWith(memberOverrides: [override]).toJson(),
          );
          expect(
            staged.toJson(),
            before.copyWith(communities: [result]).toJson(),
          );
          expect(p.settings, same(saved));
          expect(p.settings.communities!.single.memberOverrides, isNull);
          expect(p.revision, revision);
          expect(c.dirty, isTrue);
          expect(c.canEdit, isTrue);
          expect(p.reads, 1);
          expect(p.writes, 0);
          expect(p.applies, 0);

          // This is the existing public Controller save contract, not a claim
          // to have exercised the separate parent page's save-button input.
          p.failSave = true;
          expect(await c.save(), isFalse);
          await _twoFrames(t);
          expect(c.draft, same(staged));
          expect(c.dirty, isTrue);
          expect(c.canEdit, isTrue);
          expect(c.scopeEpoch, epoch);
          expect(c.revision, revision);
          expect(p.settings, same(saved));
          expect(p.revision, revision);
          expect(p.writes, 0);
          expect(p.applies, 0);

          p.failSave = false;
          expect(await c.save(), isTrue);
          await _twoFrames(t);
          expect(p.writes, 1);
          expect(c.dirty, isFalse);
          expect(c.scopeEpoch, epoch);
          expect(c.revision, revision + 1);
          expect(p.settings.toJson(), staged.toJson());
          expect(c.draft!.toJson(), staged.toJson());
          expect(p.reads, 1);
          expect(t.takeException(), isNull);
        } finally {
          await members.close(t, c, p);
          semantics.dispose();
        }
      },
      timeout: const Timeout(Duration(seconds: 45)),
    );
  }
}
