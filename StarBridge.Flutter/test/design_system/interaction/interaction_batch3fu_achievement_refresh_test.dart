import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/features/account/account_models.dart';
import 'package:starbridge_flutter/features/achievements/achievement_catalog.dart';
import 'package:starbridge_flutter/features/achievements/achievement_collection_port.dart';
import 'package:starbridge_flutter/features/achievements/achievement_collection_session.dart';
import 'package:starbridge_flutter/features/achievements/achievements_page.dart';
import 'package:starbridge_flutter/features/common/social_read_activity.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../_support/visual_output_dir.dart';
import '../../features/achievements/achievement_collection_controller_test.dart'
    show achievementTestAccount, DeferredAchievementPort;
import '../../features/friends/social_layout_test.dart' show loadFonts, size;
import 'interaction_batch3i_test.dart' show scopedApp;

const _refresh = Key('achievement-refresh');
const _reduced = Key('achievement-refresh-static');
final _review = visualOutputDir(
  'interaction_motion_batch3fu_20261017',
  legacySubdirectory: 'review',
);
final _at = DateTime.utc(2026, 10, 15, 12);
final _award = DateTime.utc(2026, 9, 4);

AchievementCollection ready(
  int generation, {
  bool earned = true,
  int progress = 4,
}) => AchievementCollection(
  generation: generation,
  status: AchievementCollectionStatus.ready,
  earnedAt: earned ? {'first-entry': _award} : {},
  progress: {'hangar-home': progress},
  synchronizedAtUtc: _at,
);

class _Port extends DeferredAchievementPort
    implements AchievementCollectionChanges {
  final content = StreamController<void>.broadcast(sync: true);
  @override
  Stream<void> get changes => content.stream;
}

class _Probe {
  _Probe(this.suite, {this.light = false, this.large = false}) {
    session = AchievementCollectionSession(
      account: account,
      port: port,
      clock: () => _at,
    );
  }
  final account = ValueNotifier<AccountProjection>(achievementTestAccount(1));
  final port = _Port();
  late final AchievementCollectionSession session;
  final capture = GlobalKey();
  InteractionSuite suite;
  bool light, large, reduce = false, visible = true;
  late StateSetter update;
  Widget app() => RepaintBoundary(
    key: capture,
    child: StatefulBuilder(
      builder: (context, state) {
        update = state;
        final base = scopedApp(
          visible
              ? AchievementsPage(
                  account: account,
                  port: port,
                  session: session,
                  catalog: achievementCatalog.take(2).toList(growable: false),
                )
              : const Text('Page closed'),
          suite,
          reduce: reduce,
          light: light,
        ) as MaterialApp;
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: base.theme,
          themeAnimationDuration: Duration.zero,
          locale: base.locale,
          supportedLocales: base.supportedLocales,
          localizationsDelegates: base.localizationsDelegates,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(large ? 1.5 : 1)),
            child: base.builder!(context, child),
          ),
          home: base.home,
        );
      },
    ),
  );
}

Future<void> frames(WidgetTester t, [int count = 24]) async {
  for (var i = 0; i < count; i++) {
    await t.pump(const Duration(milliseconds: 16));
  }
}

// ignore: library_private_types_in_public_api
Future<void> mount(WidgetTester t, _Probe p) async {
  size(t, const Size(1100, 1000));
  await t.pumpWidget(p.app());
  await frames(t);
  expect(p.port.requests, hasLength(1));
  p.port.requests.single.completion.complete(ready(1));
  await frames(t);
  expect(p.session.collection.value.isEarned('first-entry'), isTrue);
}

bool focusedInside(Finder finder) {
  final target = finder.evaluate().single;
  final focus = FocusManager.instance.primaryFocus?.context;
  if (focus == null) return false;
  var inside = identical(target, focus);
  focus.visitAncestorElements((element) {
    inside |= identical(element, target);
    return !inside;
  });
  return inside;
}

Future<void> activate(WidgetTester t, String source) async {
  final target = find.byKey(_refresh);
  await t.ensureVisible(target);
  if (source == 'keyboard') {
    var count = 0;
    while (!focusedInside(target) && count++ < 48) {
      await t.sendKeyEvent(LogicalKeyboardKey.tab);
      await t.pump();
    }
    expect(focusedInside(target), isTrue);
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
  } else if (source == 'reader') {
    final node = t.getSemantics(target);
    expect(node.getSemanticsData().hasAction(ui.SemanticsAction.tap), isTrue);
    t.binding.renderViews.single.owner!.semanticsOwner!.performAction(
      node.id,
      ui.SemanticsAction.tap,
    );
  } else {
    await t.tap(target);
  }
  await t.pump();
  await frames(t);
}

Finder get waiting => find.byType(SocialReadActivity);
void waitState(WidgetTester t, {required bool animated}) {
  expect(waiting, findsOneWidget);
  final busy = find.descendant(
    of: waiting,
    matching: find.byType(SuiteBusyFrame),
  );
  expect(InteractionScope.of(t.element(busy)).reduceMotion, !animated);
}

// ignore: library_private_types_in_public_api
Future<void> clean(WidgetTester t, _Probe p) async {
  await t.pumpWidget(const SizedBox());
  p.session.dispose();
  await p.port.content.close();
  p.account.dispose();
  expect(t.takeException(), isNull);
}

Future<List<int>> pixels(
  WidgetTester t,
  // ignore: library_private_types_in_public_api
  _Probe p,
  Rect rect, {
  String? png,
}) async {
  final boundary =
      p.capture.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  return (await t.runAsync(() async {
    final image = await boundary.toImage();
    try {
      if (png != null) {
        await Directory(_review).create(recursive: true);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File('$_review/$png.png')
            .writeAsBytes(bytes!.buffer.asUint8List());
      }
      final raw = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!
          .buffer
          .asUint8List();
      return [
        for (var y = rect.top.ceil(); y < rect.bottom.floor(); y++)
          ...raw.sublist(
            (y * image.width + rect.left.ceil()) * 4,
            (y * image.width + rect.right.floor()) * 4,
          ),
      ];
    } finally {
      image.dispose();
    }
  }))!;
}

int changed(List<int> a, List<int> b) {
  expect(a.length, b.length);
  var count = 0;
  for (var i = 0; i < a.length; i += 4) {
    if (a[i] != b[i] ||
        a[i + 1] != b[i + 1] ||
        a[i + 2] != b[i + 2] ||
        a[i + 3] != b[i + 3]) {
      count++;
    }
  }
  return count;
}

void main() {
  setUpAll(loadFonts);
  testWidgets('3fu current keyboard refresh must not loop', (t) async {
    final p = _Probe(InteractionSuite.rail);
    try {
      await mount(t, p);
      await activate(t, 'keyboard');
      final label = AppStrings.of(t.element(find.byType(AchievementsPage)))
          .text('achievements.syncing');
      final legacy = find.byWidgetPredicate(
        (w) => w is LinearProgressIndicator && w.semanticsLabel == label,
      );
      final marker = legacy.evaluate().isNotEmpty
          ? legacy
          : find.descendant(
              of: waiting,
              matching: find.byType(LinearProgressIndicator),
            );
      expect(t.widget<LinearProgressIndicator>(marker).value, isNotNull);
      p.port.requests.last.completion.complete(ready(1));
      await frames(t);
    } finally {
      await clean(t, p);
    }
  });

  for (final suite in InteractionSuite.values) {
    for (final source in ['pointer', 'keyboard', 'reader']) {
      testWidgets(
        '3fu $suite $source held refresh rejection retry preserve confirmed awards and request count',
        (t) async {
          final semantics = t.ensureSemantics();
          final p = _Probe(suite);
          try {
            await mount(t, p);
            await activate(t, source);
            waitState(t, animated: source == 'pointer');
            expect(p.port.requests, hasLength(2));
            expect(p.session.collection.value.isRefreshing, isTrue);
            expect(p.session.collection.value.dateFor('first-entry'), _award);
            expect(p.session.collection.value.synchronizedAtUtc, _at);
            expect(
              t.widget<IconButton>(find.byKey(_refresh)).onPressed,
              isNull,
            );
            expect(
              t
                  .getSemantics(find.byKey(_refresh))
                  .getSemanticsData()
                  .hasAction(ui.SemanticsAction.tap),
              isFalse,
            );
            await t.tap(find.byKey(_refresh), warnIfMissed: false);
            await t.pump();
            expect(p.port.requests, hasLength(2));
            p.port.requests[1].completion.completeError(
              TimeoutException('test read timeout'),
            );
            await frames(t);
            expect(waiting, findsNothing);
            expect(
              find.byKey(const Key('achievement-sync-failed')),
              findsOneWidget,
            );
            expect(p.session.collection.value.isEarned('first-entry'), isTrue);
            final retrySource = source == 'pointer' ? 'keyboard' : 'pointer';
            await activate(t, retrySource);
            waitState(t, animated: retrySource == 'pointer');
            expect(p.port.requests, hasLength(3));
            p.port.requests.last.completion.complete(
              ready(1, earned: false, progress: 2),
            );
            await frames(t);
            expect(p.session.collection.value.dateFor('first-entry'), _award);
            expect(p.session.collection.value.progressFor('hangar-home'), 4);
            expect(p.session.collection.value.refreshFailed, isFalse);
          } finally {
            await clean(t, p);
            semantics.dispose();
          }
        },
      );
    }

    testWidgets(
      '3fu $suite queued passive followup does not inherit manual pointer origin',
      (t) async {
        final p = _Probe(suite);
        try {
          await mount(t, p);
          await activate(t, 'pointer');
          waitState(t, animated: true);
          for (var i = 0; i < 10; i++) {
            p.port.content.add(null);
          }
          await t.pump();
          expect(p.port.requests, hasLength(2));
          p.port.requests[1].completion.complete(ready(1));
          await frames(t);
          expect(p.port.requests, hasLength(3));
          waitState(t, animated: false);
          p.port.requests[2].completion.complete(ready(1));
          await frames(t);
          expect(p.port.requests, hasLength(3));
          expect(waiting, findsNothing);
        } finally {
          await clean(t, p);
        }
      },
    );

    testWidgets(
      '3fu $suite remount joins existing read with unknown static provenance',
      (t) async {
        final p = _Probe(suite);
        try {
          await mount(t, p);
          await activate(t, 'pointer');
          p.update(() {
            p.visible = false;
          });
          await frames(t);
          p.update(() {
            p.visible = true;
          });
          await frames(t);
          expect(p.port.requests, hasLength(2));
          waitState(t, animated: false);
          p.port.requests[1].completion.complete(ready(1));
          await frames(t);
          expect(p.session.collection.value.isRefreshing, isFalse);
        } finally {
          await clean(t, p);
        }
      },
    );

    for (final failure in [false, true]) {
      testWidgets(
        '3fu $suite leave then late failure=$failure retains session and original reopening rule',
        (t) async {
          final p = _Probe(suite);
          try {
            await mount(t, p);
            await activate(t, 'pointer');
            p.update(() {
              p.visible = false;
            });
            await frames(t);
            if (failure) {
              p.port.requests[1].completion.completeError(
                TimeoutException('late read failure'),
              );
            } else {
              p.port.requests[1].completion.complete(ready(1));
            }
            await frames(t);
            expect(p.session.collection.value.isEarned('first-entry'), isTrue);
            expect(p.session.collection.value.refreshFailed, failure);
            p.update(() {
              p.visible = true;
            });
            await frames(t);
            expect(p.port.requests, hasLength(failure ? 3 : 2));
            if (failure) {
              waitState(t, animated: false);
              p.port.requests[2].completion.complete(ready(1));
              await frames(t);
            }
            expect(p.session.collection.value.isEarned('first-entry'), isTrue);
          } finally {
            await clean(t, p);
          }
        },
      );
    }

    testWidgets(
      '3fu $suite signout while refreshing rejects old award receipt',
      (t) async {
        final p = _Probe(suite);
        try {
          await mount(t, p);
          await activate(t, 'pointer');
          p.account.value = achievementTestAccount(2, signedIn: false);
          await frames(t);
          p.port.requests[1].completion.complete(ready(1));
          await frames(t);
          expect(p.session.collection.value.earnedAt, isEmpty);
          expect(
            p.session.collection.value.status,
            AchievementCollectionStatus.signedOut,
          );
          expect(p.port.requests, hasLength(2));
          expect(waiting, findsNothing);
        } finally {
          await clean(t, p);
        }
      },
    );

    for (final light in [false, true]) {
      testWidgets(
        '3fu $suite light=$light pointer pixels stop at live user reduce',
        (t) async {
          final p = _Probe(suite, light: light, large: true);
          try {
            await mount(t, p);
            final pageContext = t.element(find.byType(AchievementsPage));
            await t.runAsync(() async {
              await precacheImage(
                AssetImage(achievementCatalog.first.earnedAsset),
                pageContext,
              );
              await precacheImage(
                AssetImage(achievementCatalog[1].lockedAsset),
                pageContext,
              );
            });
            await t.pump();
            // This control is already visible. Avoid the helper's deliberate
            // ensureVisible scroll so the review shows the full page heading.
            await t.tap(find.byKey(_refresh));
            await t.pump();
            await frames(t);
            waitState(t, animated: true);
            final rect = t.getRect(waiting);
            final first = await pixels(
              t,
              p,
              rect,
              png: '${suite.name}-${light ? 'light' : 'dark'}',
            );
            await frames(t, 17);
            final moving = changed(first, await pixels(t, p, rect));
            expect(moving, greaterThan(0));
            p.update(() {
              p.reduce = true;
            });
            await t.pump();
            await t.pump();
            expect(waiting, findsNothing);
            expect(find.byKey(_reduced), findsOneWidget);
            final textRect = t.getRect(find.byKey(_reduced));
            final reduced = await pixels(t, p, textRect);
            await frames(t, 38);
            final staticPixels = changed(reduced, await pixels(t, p, textRect));
            expect(staticPixels, 0);
            expect(t.getRect(find.byKey(_reduced)), textRect);
            p.update(() {
              p.reduce = false;
            });
            await t.pump();
            await t.pump();
            waitState(t, animated: true);
            expect(t.getRect(waiting), rect);
            expect(p.port.requests, hasLength(2));
            await t.runAsync(
              () =>
                  File(
                    '$_review/${suite.name}-${light ? 'light' : 'dark'}.json',
                  ).writeAsString(
                    jsonEncode({
                      'movingPixels': moving,
                      'reducedStaticPixels': staticPixels,
                      'marker': [rect.left, rect.top, rect.width, rect.height],
                      'staticText': [
                        textRect.left,
                        textRect.top,
                        textRect.width,
                        textRect.height,
                      ],
                    }),
                  ),
            );
            p.port.requests[1].completion.complete(ready(1));
            await frames(t);
          } finally {
            await clean(t, p);
          }
        },
        skip: const bool.fromEnvironment('STARBRIDGE_PUBLIC_SOURCE'),
      );
    }
  }
}
