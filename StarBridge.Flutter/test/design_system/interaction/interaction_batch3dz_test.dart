import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_dialog.dart';
import 'package:starbridge_flutter/features/communities/communities_module.dart';
import 'package:starbridge_flutter/features/communities/communities_page.dart';
import 'package:starbridge_flutter/features/communities/community_directory_details.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import 'interaction_batch3aj_test.dart' show Directory, Privacy, page;
import 'interaction_batch3ac_test.dart' show Live, LiveState, mount;
import 'interaction_batch3ae_test.dart' show action;
import '../../features/friends/social_layout_test.dart' show loadFonts;

const _timeout = Timeout(Duration(seconds: 45));
const _details = ValueKey('community-directory-details');
const _bodyOpen = ValueKey('community-card-open-org-a');

Future<void> _frames(WidgetTester t, {int count = 6}) async {
  for (var i = 0; i < count; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

/// The existing directory fixture supplies public rows and real module ports.
/// All user entry points below are real card/button/focus/reader activations.
class _Fixture {
  final port = Directory();
  late final owner = CommunitiesModule(port);
  late final privacy = Privacy(port.invites.calls);
  late final child = page(port, owner, privacy);

  Future<LiveState> show(
    WidgetTester t,
    InteractionSuite suite, {
    Locale locale = const Locale('zh', 'CN'),
  }) => mount(t, child, suite, locale: locale);

  void expectReadOnly() {
    expect(port.writes, isEmpty);
    expect(port.invites.acceptedRequests, isEmpty);
    expect(privacy.sources.where((item) => item.$1 == 'privacy-save'), isEmpty);
    expect(port.recovery, isEmpty);
    expect(owner.selected, isNull);
  }

  Future<void> close(WidgetTester t) async {
    await t.pumpWidget(const SizedBox.shrink());
    await _frames(t, count: 2);
    owner.dispose();
    await t.runAsync(() async {
      await port.disposeFixtures();
      await privacy.events.close();
    });
  }
}

Future<StarBridgeDialogRoute<dynamic>> _openDetails(
  WidgetTester t,
  String source,
) async {
  if (source == 'keyboard') {
    // Reuse the actual card body's focus target, not a nested primary button.
    final target = find.byKey(_bodyOpen);
    await t.ensureVisible(target);
    final focus = find
        .descendant(
          of: target,
          matching: find.byWidgetPredicate(
            (w) => w is Focus && w.focusNode?.canRequestFocus == true,
          ),
        )
        .first;
    t.widget<Focus>(focus).focusNode!.requestFocus();
    await t.pump();
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
  } else {
    await action(t, _bodyOpen, source, settle: false);
  }
  await _frames(t);
  final details = find.byType(CommunityDirectoryDetails);
  expect(details, findsOneWidget);
  final route = ModalRoute.of(t.element(details))! as StarBridgeDialogRoute;
  expect(route.instant, source != 'pointer');
  return route;
}

Future<void> _retire(
  WidgetTester t,
  LiveState live,
  _Fixture fixture,
  StarBridgeDialogRoute<dynamic> route, {
  required bool confirmation,
}) async {
  live.change(() => live.visible = false);
  await t.pump();
  expect(
    t.takeException(),
    isNull,
    reason: 'Retiring an owned route may still run its builder after the page context is inactive.',
  );
  await _frames(t);
  expect(find.byType(CommunitiesPage, skipOffstage: false), findsNothing);
  expect(find.byKey(_details, skipOffstage: false), findsNothing);
  expect(
    find.byType(CommunityDirectoryDetails, skipOffstage: false),
    findsNothing,
  );
  if (confirmation) {
    expect(
      find.byKey(const Key('community-command-confirm'), skipOffstage: false),
      findsNothing,
    );
    expect(find.byType(AlertDialog, skipOffstage: false), findsNothing);
  }
  expect(route.isActive, isFalse);
  fixture.expectReadOnly();
  // The owner is still independently alive; a later original read must not
  // revive a retired page/route or call its inherited context.
  final reads = fixture.port.reads.length;
  await fixture.owner.refresh(force: true);
  await _frames(t, count: 2);
  expect(fixture.port.reads.length, reads + 1);
  expect(
    find.byType(CommunityDirectoryDetails, skipOffstage: false),
    findsNothing,
  );
  fixture.expectReadOnly();
  expect(t.takeException(), isNull);
}

String _detailsTitle(Locale locale) =>
    locale.languageCode == 'en' ? 'Organization details' : '組織詳情';
String _aboutTitle(Locale locale) =>
    locale.languageCode == 'en' ? 'About the organization' : '組織介紹';
String _closeCopy(Locale locale) =>
    locale.languageCode == 'en' ? 'Close' : '關閉';

void _expectCallerCopy(WidgetTester t, Locale locale) {
  final details = find.byType(CommunityDirectoryDetails);
  for (final copy in [
    _detailsTitle(locale),
    _aboutTitle(locale),
    _closeCopy(locale),
  ]) {
    expect(
      find.descendant(of: details, matching: find.text(copy)),
      findsWidgets,
    );
  }
  // Root Navigator is CN in this fixture. The page's local override, not the
  // overlay's language, owns these strings.
  expect(
    find.descendant(of: details, matching: find.text('组织详情')),
    findsNothing,
  );
}

void main() {
  setUpAll(loadFonts);
  for (final suite in InteractionSuite.values) {
    for (final source in ['pointer', 'keyboard', 'reader']) {
      testWidgets(
        '$suite $source actual directory details retire with their page without stale-context lookup or writes',
        (t) async {
          final semantics = t.ensureSemantics();
          final fixture = _Fixture();
          try {
            final live = await fixture.show(t, suite);
            final route = await _openDetails(t, source);
            fixture.expectReadOnly();
            await _retire(t, live, fixture, route, confirmation: false);
          } finally {
            await fixture.close(t);
            semantics.dispose();
          }
        },
        timeout: _timeout,
      );
    }

    for (final locale in [const Locale('en'), const Locale('zh', 'TW')]) {
      testWidgets(
        '$suite caller $locale copy remains live through same-key locale switch and actual directory refresh',
        (t) async {
          final fixture = _Fixture();
          try {
            final live = await fixture.show(t, suite, locale: locale);
            final route = await _openDetails(t, 'pointer');
            final detailsState = t.state(
              find.byType(CommunityDirectoryDetails),
            );
            final caller = AppStrings.of(
              t.element(find.byType(CommunitiesPage)),
            );
            expect(
              caller.text('communities.details.title'),
              _detailsTitle(locale),
            );
            _expectCallerCopy(t, locale);
            final next = locale.languageCode == 'en'
                ? const Locale('zh', 'TW')
                : const Locale('en');
            await t.pumpWidget(
              Live(fixture.child, suite, key: live.widget.key, locale: next),
            );
            await _frames(t, count: 2);
            expect(t.state<LiveState>(find.byType(Live)), same(live));
            final reads = fixture.port.reads.length;
            // An actual owner notification rebuilds the still-open details.
            // No test directly calls a dialog builder or translation callback.
            await fixture.owner.refresh(force: true);
            await _frames(t);
            expect(fixture.port.reads.length, reads + 1);
            expect(
              t.state(find.byType(CommunityDirectoryDetails)),
              same(detailsState),
            );
            expect(
              ModalRoute.of(t.element(find.byType(CommunityDirectoryDetails))),
              same(route),
            );
            _expectCallerCopy(t, next);
            expect(
              find.descendant(
                of: find.byType(CommunityDirectoryDetails),
                matching: find.text(_detailsTitle(locale)),
              ),
              findsNothing,
            );
            fixture.expectReadOnly();
            await _retire(t, live, fixture, route, confirmation: false);
          } finally {
            await fixture.close(t);
          }
        },
        timeout: _timeout,
      );
    }

    testWidgets(
      '$suite explicit card command confirmation retires safely while its parent page leaves',
      (t) async {
        final fixture = _Fixture();
        try {
          final live = await fixture.show(t, suite);
          // This is the existing public primary action. Never invoke State.act
          // or the business port directly merely to fabricate a confirmation.
          await action(
            t,
            const ValueKey('community-card-primary-org-a'),
            'pointer',
            settle: false,
          );
          await _frames(t);
          expect(find.byType(CommunityDirectoryDetails), findsNothing);
          final confirm = find.byKey(const Key('community-command-confirm'));
          expect(confirm, findsOneWidget);
          expect(find.byType(AlertDialog), findsOneWidget);
          final route =
              ModalRoute.of(t.element(confirm))! as StarBridgeDialogRoute;
          fixture.expectReadOnly();
          await _retire(t, live, fixture, route, confirmation: true);
        } finally {
          await fixture.close(t);
        }
      },
      timeout: _timeout,
    );

    testWidgets(
      '$suite open details retain real live suite palette and reduce relay before safe retirement',
      (t) async {
        final fixture = _Fixture();
        try {
          final live = await fixture.show(t, suite);
          final route = await _openDetails(t, 'pointer');
          final state = t.state(find.byType(CommunityDirectoryDetails));
          final next = InteractionSuite
              .values[(suite.index + 1) % InteractionSuite.values.length];
          live.change(() {
            live.suite = next;
            live.light = true;
            live.reduce = true;
          });
          await t.pump();
          await t.pump();
          final data = InteractionScope.of(
            t.element(find.byType(CommunityDirectoryDetails)),
          );
          expect(data.suite, next);
          expect(data.palette.brightness, Brightness.light);
          expect(data.reduceMotion, isTrue);
          expect(route.animation!.value, 1);
          expect(t.state(find.byType(CommunityDirectoryDetails)), same(state));
          await fixture.owner.refresh(force: true);
          await _frames(t, count: 2);
          final refreshed = InteractionScope.of(
            t.element(find.byType(CommunityDirectoryDetails)),
          );
          expect(refreshed.suite, next);
          expect(refreshed.palette.brightness, Brightness.light);
          expect(refreshed.reduceMotion, isTrue);
          fixture.expectReadOnly();
          await _retire(t, live, fixture, route, confirmation: false);
        } finally {
          await fixture.close(t);
        }
      },
      timeout: _timeout,
    );
  }
}
