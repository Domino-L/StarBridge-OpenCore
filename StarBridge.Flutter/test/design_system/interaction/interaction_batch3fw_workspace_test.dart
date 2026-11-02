import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/icons/standard_icon.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_activation_origin.dart';
import 'package:starbridge_flutter/features/common/social_read_activity.dart';
import 'package:starbridge_flutter/features/communities/communities_module.dart';
import 'package:starbridge_flutter/features/communities/community_workspace_controller.dart';
import 'package:starbridge_flutter/features/communities/community_workspace_port.dart';
import 'package:starbridge_flutter/features/communities/community_workspace_session.dart';
import 'package:starbridge_flutter/features/communities/community_workspace_view.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../_support/visual_output_dir.dart';
import '../../features/communities/community_workspace_test.dart'
    show WorkspaceTestPort, workspacePayload;
import '../../features/friends/social_layout_test.dart' show loadFonts, size;
import 'interaction_batch3i_test.dart' show scopedApp;
import 'interaction_batch3fv_directory_test.dart' show frames, changed;
import 'interaction_batch3fv_directory_test.dart' as directory show activate;

final _review = visualOutputDir(
  'interaction_motion_batch3fw_20261017',
  legacySubdirectory: 'review',
);
const _target = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _refresh = Key('community-workspace-refresh');
const _progress = ValueKey('community-refresh-progress');
const _search = Key('community-member-search-submit');

Future<void> activate(WidgetTester t, Key key, String source) async {
  final target = find.byKey(key);
  // Standard's icon has no Text/ExcludeFocus child for the old text helper.
  // Request its real supplied focus node, then send an actual Enter event.
  if (source == 'keyboard' && t.widget(target) is IconButton) {
    t.widget<IconButton>(target).focusNode!.requestFocus();
    await t.pump();
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pump();
    await frames(t);
  } else {
    await directory.activate(t, key, source);
  }
}

class _Read {
  _Read(this.target, this.query, this.offset);
  final String target, query;
  final int offset;
  final result = Completer<CommunityWorkspace>();
}

class _Probe {
  _Probe(
    this.suite, {
    this.light = false,
    this.large = false,
    this.openingSource = InteractionSource.pointer,
  }) {
    port.reader = (target, query, offset) {
      final read = _Read(target, query, offset);
      reads.add(read);
      return read.result.future;
    };
  }
  final port = WorkspaceTestPort();
  final session = CommunityWorkspaceSession();
  final reads = <_Read>[];
  final renewals = <Completer<void>>[];
  final capture = GlobalKey();
  final page = GlobalKey<CommunityWorkspaceViewState>();
  final InteractionSource openingSource;
  InteractionSuite suite;
  bool light, large, reduce = false, visible = true, heldRenewal = false;
  String target = _target, organization = 'organization-one';
  late StateSetter update;
  CommunityWorkspaceController get model => page.currentState!.model;
  Future<void> renew() {
    final result = Completer<void>();
    renewals.add(result);
    if (!heldRenewal) result.complete();
    return result.future;
  }

  void complete(
    int index, {
    String name = 'Organization A',
    bool next = false,
  }) {
    final r = reads[index];
    final payload = workspacePayload(target: r.target, query: r.query)
      ..['name'] = name
      ..['offset'] = r.offset
      ..['next'] = next ? r.offset + 20 : null
      ..['matchedCount'] = next ? 40 : r.offset + 1
      ..['totalCount'] = next ? 40 : r.offset + 1;
    if (next) {
      final prototype = Map<String, Object?>.from(
        (payload['members'] as List).single as Map,
      );
      payload['members'] = [
        for (var i = 0; i < 20; i++)
          {
            ...prototype,
            'memberRef': (i + 1).toRadixString(16).padLeft(32, '0'),
            'callsign': '分页成员 $i',
            'isSelf': i == 0,
          },
      ];
    }
    r.result.complete(CommunityWorkspace.parse(payload));
  }

  Widget app() => RepaintBoundary(
    key: capture,
    child: StatefulBuilder(
      builder: (context, state) {
        update = state;
        final base = scopedApp(
          Builder(
            builder: (context) => starBridgeInitialReadViewport(
              context,
              source: openingSource,
              child: visible
                  ? CommunityWorkspaceView(
                      key: page,
                      port: port,
                      targetRef: target,
                      organizationKey: organization,
                      session: session,
                      onGovernanceChanged: renew,
                    )
                  : const Text('Closed'),
            ),
          ),
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

// ignore: library_private_types_in_public_api
Future<void> mount(WidgetTester t, _Probe p, {bool ready = true}) async {
  size(t, const Size(1200, 1100));
  await t.pumpWidget(p.app());
  await frames(t);
  expect(p.reads, hasLength(1));
  if (ready) {
    p.complete(0);
    await frames(t);
    expect(p.model.workspace, isNotNull);
  }
}

void state(WidgetTester t, {required bool animated, bool initial = false}) {
  if (initial) {
    final circles = find.byType(CircularProgressIndicator);
    if (circles.evaluate().isNotEmpty) {
      expect(
        t.widget<CircularProgressIndicator>(circles).value,
        animated ? isNull : isNotNull,
      );
      return;
    }
    if (find
        .byWidgetPredicate(
          (w) =>
              w is StandardIcon &&
              w.semantic == StandardIconSemantic.hourglassTop,
        )
        .evaluate()
        .isNotEmpty) {
      expect(animated, isFalse);
      return;
    }
    expect(find.byType(SocialReadActivity), findsOneWidget);
    final busy = find.descendant(
      of: find.byType(SocialReadActivity),
      matching: find.byType(SuiteBusyFrame),
    );
    expect(InteractionScope.of(t.element(busy)).reduceMotion, !animated);
    return;
  }
  final marker = find.byKey(_progress);
  expect(marker, findsOneWidget);
  expect(t.widget(marker), isA<SocialReadActivity>());
  final busy = find.descendant(
    of: marker,
    matching: find.byType(SuiteBusyFrame),
  );
  expect(InteractionScope.of(t.element(busy)).reduceMotion, !animated);
}

// ignore: library_private_types_in_public_api
Future<void> clean(WidgetTester t, _Probe p) async {
  await t.pumpWidget(const SizedBox());
  p.session.clear();
  await p.port.changes.close();
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
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        await File('$_review/$png.png')
            .writeAsBytes(data!.buffer.asUint8List());
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

void main() {
  setUpAll(loadFonts);
  testWidgets('3fw keyboard initial workspace must not loop', (t) async {
    final p = _Probe(
      InteractionSuite.standard,
      openingSource: InteractionSource.keyboard,
    );
    try {
      await mount(t, p, ready: false);
      state(t, animated: false, initial: true);
      p.complete(0);
      await frames(t);
    } finally {
      await clean(t, p);
    }
  });

  for (final suite in InteractionSuite.values) {
    for (final source in ['pointer', 'keyboard', 'reader']) {
      testWidgets('3fw $suite $source initial and live reduce', (t) async {
        final semantics = t.ensureSemantics();
        final p = _Probe(
          suite,
          openingSource: source == 'pointer'
              ? InteractionSource.pointer
              : InteractionSource.keyboard,
        );
        try {
          await mount(t, p, ready: false);
          state(t, animated: source == 'pointer', initial: true);
          p.update(() => p.reduce = true);
          await frames(t, 2);
          state(t, animated: false, initial: true);
          p.complete(0);
          await frames(t);
          expect(p.reads, hasLength(1));
        } finally {
          await clean(t, p);
          semantics.dispose();
        }
      });
      testWidgets('3fw $suite $source refresh after held renewal and retry', (
        t,
      ) async {
        final semantics = t.ensureSemantics();
        final p = _Probe(suite)..heldRenewal = true;
        try {
          await mount(t, p);
          final before = p.model.workspace;
          await activate(t, _refresh, source);
          expect(p.renewals, hasLength(1));
          expect(p.reads, hasLength(1));
          await activate(t, _refresh, source);
          expect(p.renewals, hasLength(1));
          p.renewals[0].complete();
          await frames(t);
          expect(p.reads, hasLength(2));
          expect(p.model.workspace, same(before));
          state(t, animated: source == 'pointer');
          p.reads[1].result.completeError(
            const CommunityFailure('unavailable'),
          );
          await frames(t);
          expect(p.model.workspace, same(before));
          expect(p.model.error, 'unavailable');
          expect(find.byKey(_progress), findsNothing);
          final reverse = source == 'pointer' ? 'keyboard' : 'pointer';
          await activate(
            t,
            const Key('community-workspace-refresh-error'),
            reverse,
          );
          expect(p.reads, hasLength(3));
          state(t, animated: reverse == 'pointer');
          p.complete(2, name: 'Fresh organization');
          await frames(t);
          expect(p.model.workspace!.name, 'Fresh organization');
          expect(find.byKey(_progress), findsNothing);
        } finally {
          await clean(t, p);
          semantics.dispose();
        }
      });
    }

    testWidgets('3fw $suite member query replacement and old reply', (t) async {
      final p = _Probe(suite);
      try {
        await mount(t, p);
        p.page.currentState!.search.text = 'first';
        await activate(t, _search, 'pointer');
        state(t, animated: true);
        final phase = t.widget<SocialReadActivity>(find.byKey(_progress)).key;
        p.page.currentState!.search.text = 'second';
        await activate(t, _search, 'keyboard');
        state(t, animated: false);
        expect(p.reads, hasLength(3));
        expect(p.reads[2].query, 'second');
        p.complete(1, name: 'Stale organization');
        await frames(t);
        expect(p.model.busy, isTrue);
        expect(p.model.workspace!.name, 'Organization A');
        expect(t.widget<SocialReadActivity>(find.byKey(_progress)).key, phase);
        state(t, animated: false);
        p.complete(2, name: 'Latest organization');
        await frames(t);
        expect(p.model.workspace!.query, 'second');
        expect(p.model.workspace!.name, 'Latest organization');
      } finally {
        await clean(t, p);
      }
    });

    testWidgets(
      '3fw $suite silent activity remains quiet and borrowed return',
      (t) async {
        final p = _Probe(suite);
        try {
          await mount(t, p);
          final owner = p.model;
          final refresh = owner.refreshFromActivity();
          await frames(t);
          expect(owner.busy, isTrue);
          expect(find.byKey(_progress), findsNothing);
          expect(find.byType(SocialReadActivity), findsNothing);
          p.update(() => p.visible = false);
          await frames(t);
          p.complete(1, name: 'Background organization');
          await refresh;
          p.update(() => p.visible = true);
          await frames(t);
          expect(p.model, same(owner));
          expect(p.model.workspace!.name, 'Background organization');
          expect(p.reads, hasLength(2));
        } finally {
          await clean(t, p);
        }
      },
    );

    testWidgets('3fw $suite next and previous retain actual source', (t) async {
      final p = _Probe(suite);
      try {
        await mount(t, p, ready: false);
        p.complete(0, next: true);
        await frames(t);
        await activate(t, const Key('community-member-next-page'), 'keyboard');
        expect(p.reads, hasLength(2));
        expect(p.reads[1].offset, 20);
        state(t, animated: false);
        p.complete(1);
        await frames(t);
        await activate(
          t,
          const Key('community-member-previous-page'),
          'pointer',
        );
        expect(p.reads, hasLength(3));
        expect(p.reads[2].offset, 0);
        state(t, animated: true);
        p.complete(2);
        await frames(t);
      } finally {
        await clean(t, p);
      }
    });

    testWidgets(
      '3fw $suite remount pending read is unknown and late invalidated',
      (t) async {
        final p = _Probe(suite);
        try {
          await mount(t, p);
          final owner = p.model;
          await activate(t, _refresh, 'pointer');
          state(t, animated: true);
          p.update(() => p.visible = false);
          await frames(t);
          p.update(() => p.visible = true);
          await frames(t);
          expect(p.model, same(owner));
          expect(p.reads, hasLength(2));
          state(t, animated: false);
          p.port.changes.add(null);
          await frames(t);
          expect(p.model.workspace, isNull);
          expect(p.model.error, 'identityUnavailable');
          p.complete(1, name: 'Must not resurrect');
          await frames(t);
          expect(p.model.workspace, isNull);
          expect(find.text('Must not resurrect'), findsNothing);
        } finally {
          await clean(t, p);
        }
      },
    );

    testWidgets('3fw $suite passive followup does not reuse manual marker', (
      t,
    ) async {
      final p = _Probe(suite);
      try {
        await mount(t, p);
        await activate(t, _refresh, 'pointer');
        state(t, animated: true);
        await p.model.refreshFromActivity();
        expect(p.reads, hasLength(2));
        p.complete(1);
        await frames(t);
        expect(p.reads, hasLength(3));
        expect(p.model.busy, isTrue);
        expect(p.model.showProgress, isFalse);
        expect(find.byKey(_progress), findsNothing);
        expect(find.byType(SocialReadActivity), findsNothing);
        p.complete(2);
        await frames(t);
        expect(p.reads, hasLength(3));
      } finally {
        await clean(t, p);
      }
    });

    testWidgets(
      '3fw $suite same organization reference renewal remains guarded',
      (t) async {
        final p = _Probe(suite);
        try {
          await mount(t, p);
          final owner = p.model;
          p.update(() => p.target = 'd' * 32);
          await frames(t);
          expect(p.model, same(owner));
          expect(p.model.renewingReference, isTrue);
          expect(p.model.workspace!.name, 'Organization A');
          final guard = t.widget<AbsorbPointer>(
            find.byKey(const ValueKey('community-reference-guard')),
          );
          expect(guard.absorbing, isTrue);
          state(t, animated: false);
          p.reads[1].result.completeError(const CommunityFailure('notAllowed'));
          await frames(t);
          expect(p.model.workspace, isNull);
          expect(p.model.error, 'notAllowed');
          expect(find.byKey(_progress), findsNothing);
          expect(p.reads, hasLength(2));
        } finally {
          await clean(t, p);
        }
      },
    );

    testWidgets('3fw $suite renewal leave and stale target reply', (t) async {
      final p = _Probe(suite)..heldRenewal = true;
      try {
        await mount(t, p);
        await activate(t, _refresh, 'pointer');
        p.update(() {
          p.target = 'c' * 32;
          p.organization = 'organization-two';
        });
        await frames(t);
        expect(p.reads, hasLength(2));
        p.renewals.single.complete();
        await frames(t);
        expect(p.reads, hasLength(2));
        p.complete(1, name: 'Other organization');
        await frames(t);
        expect(p.model.workspace!.name, 'Other organization');
        p.update(() => p.visible = false);
        await frames(t);
      } finally {
        await clean(t, p);
      }
    });

    for (final light in [false, true]) {
      testWidgets('3fw review $suite light=$light large and live reduce', (
        t,
      ) async {
        final p = _Probe(suite, light: light, large: true);
        try {
          await mount(t, p, ready: false);
          final initial = const Rect.fromLTWH(480, 480, 240, 140);
          final name = '${suite.name}-${light ? 'light' : 'dark'}';
          await pixels(t, p, initial, png: '$name-initial');
          p.update(() => p.reduce = true);
          await frames(t, 2);
          final a = await pixels(t, p, initial);
          await frames(t, 38);
          final initialReduced = changed(a, await pixels(t, p, initial));
          expect(initialReduced, 0);
          p.complete(0);
          await frames(t);
          p.update(() => p.reduce = false);
          await frames(t, 2);
          await activate(t, _refresh, 'pointer');
          state(t, animated: true);
          final rect = t.getRect(find.byKey(_progress));
          final first = await pixels(t, p, rect, png: name);
          await frames(t, 12);
          final moving = changed(first, await pixels(t, p, rect));
          expect(moving, greaterThan(0));
          p.update(() => p.reduce = true);
          await frames(t, 2);
          state(t, animated: false);
          final reduced = await pixels(t, p, rect);
          await frames(t, 38);
          final staticPixels = changed(reduced, await pixels(t, p, rect));
          expect(staticPixels, 0);
          expect(t.getRect(find.byKey(_progress)), rect);
          await t.runAsync(
            () => File('$_review/$name.json').writeAsString(
              jsonEncode({
                'movingPixels': moving,
                'staticPixels': staticPixels,
                'initialReducedPixels': initialReduced,
                'rect': [rect.left, rect.top, rect.width, rect.height],
              }),
            ),
          );
          expect(p.reads, hasLength(2));
          p.complete(1);
          await frames(t);
        } finally {
          await clean(t, p);
        }
      });
    }
  }
}
