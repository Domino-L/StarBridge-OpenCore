import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_switch.dart';
import 'package:starbridge_flutter/features/settings/friend_sharing_setting.dart';
import 'package:starbridge_flutter/features/settings/game_id_visibility_setting.dart';
import 'package:starbridge_flutter/features/settings/help_support_waiting.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_connection.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';
import 'package:starbridge_flutter/platform/bridge/in_memory_bridge_connection.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../_support/visual_output_dir.dart';
import 'interaction_batch3do_test.dart' show scopedApp, size;
import 'interaction_batch3dp_visual_test.dart' show loadVisualFonts;

const _frame = Key('3du-visual-frame');
const _timeout = Timeout(Duration(seconds: 60));
final _output = visualOutputDir('interaction_motion_batch3du_20261016');
const _locales = [Locale('zh', 'CN'), Locale('zh', 'TW'), Locale('en')];
const _friendFields = [
  'presence',
  'serverRelation',
  'serverDetails',
  'ship',
  'location',
  'lastOnline',
];
const _gameFields = ['organization', 'room', 'friends', 'profile'];

Future<void> _frames(WidgetTester t, {int count = 4}) async {
  for (var i = 0; i < count; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

class _Bridge {
  _Bridge(this.kind) {
    final pair = InMemoryBridgeConnection.createPair();
    host = pair.host;
    session = BridgeClientSession(connection: pair.client, sessionGeneration: 4)
      ..acceptHostCapabilities([
        kind == 'friend'
            ? 'friendSharing.settings'
            : 'gameIdVisibility.settings',
      ]);
    subscription = host.incoming.listen((request) {
      requests.add(request);
      if (request.name == 'account.getCurrent') {
        unawaited(
          reply(request, const {'schemaVersion': 1, 'state': 'signedIn'}),
        );
      }
    });
  }
  final String kind;
  late final BridgeConnection host;
  late final BridgeClientSession session;
  late final StreamSubscription<BridgeEnvelope> subscription;
  final requests = <BridgeEnvelope>[];
  String get prefix => kind == 'friend' ? 'friendSharing' : 'gameIdVisibility';
  List<BridgeEnvelope> get reads =>
      requests.where((r) => r.name == '$prefix.read').toList();
  List<BridgeEnvelope> get saves =>
      requests.where((r) => r.name == '$prefix.save').toList();
  List<String> get fields => kind == 'friend' ? _friendFields : _gameFields;
  Key control(String field) =>
      Key(kind == 'friend' ? 'friend-sharing-$field' : 'game-id-$field');
  String titleKey(String field) => kind == 'friend'
      ? 'settings.privacy.field.$field'
      : 'settings.privacy.gameId.$field';
  Widget get setting => kind == 'friend'
      ? FriendSharingSetting(session: session)
      : GameIdVisibilitySetting(session: session);

  Map<String, Object?> snapshot({BridgeEnvelope? save}) {
    final revision = save == null
        ? 7
        : (save.payload['expectedRevision'] as int) + 1;
    return kind == 'friend'
        ? {
            'state': 'inactive',
            'snapshot': {
              'schemaVersion': 1,
              'revision': revision,
              'operationId': save?.payload['operationId'] ?? '0' * 32,
              'appliedAt': '2026-10-16T00:00:00Z',
              'fields': save?.payload['fields'] ?? 0,
            },
          }
        : {
            'schemaVersion': 1,
            'revision': revision,
            'locations': save?.payload['locations'] ?? 0,
            'canConfigure': true,
            'identityStamp': 'a' * 64,
          };
  }

  Future<void> reply(BridgeEnvelope request, Map<String, Object?> payload) =>
      host.send(
        BridgeEnvelope(
          protocolVersion: 1,
          messageType: 'response',
          name: request.name,
          correlationId: request.correlationId,
          sessionGeneration: request.sessionGeneration,
          accountContext: const BridgeAccountContext(
            environment: 'test',
            authority: 'scm',
            subject: '3du-visual',
          ),
          status: 'ok',
          payload: payload,
        ),
      );
  Future<void> close() async {
    await subscription.cancel();
    await session.close();
    await host.close();
  }
}

Widget _app(
  _Bridge bridge,
  InteractionSuite suite,
  ScrollController scroll, {
  bool light = false,
  bool reduce = false,
  bool themeOnly = false,
  double scale = 1,
  Locale locale = const Locale('zh', 'CN'),
  Widget? reference,
}) {
  final content = Builder(
    builder: (context) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: TextScaler.linear(scale)),
      child: SizedBox.expand(
        child: SingleChildScrollView(
          controller: scroll,
          padding: const EdgeInsets.all(12),
          child: reference ?? bridge.setting,
        ),
      ),
    ),
  );
  final base = scopedApp(
    content,
    suite,
    light: light,
    reduce: reduce,
    locale: locale,
  ) as MaterialApp;
  // Theme-only composition is intentional regression coverage: consumers must
  // resolve their actual theme rather than assume an external InteractionScope.
  final app = themeOnly
      ? MaterialApp(
          theme: base.theme,
          themeAnimationDuration: Duration.zero,
          locale: base.locale,
          supportedLocales: base.supportedLocales,
          localizationsDelegates: base.localizationsDelegates,
          home: Scaffold(body: content),
        )
      : base;
  return RepaintBoundary(key: _frame, child: app);
}

Future<void> _ready(WidgetTester t, _Bridge bridge) async {
  await _frames(t, count: 2);
  expect(bridge.reads, hasLength(1));
  await bridge.reply(bridge.reads.single, bridge.snapshot());
  await _frames(t);
  expect(find.byType(HelpSupportWaiting), findsNothing);
}

Finder _outer(_Bridge bridge, String field) => find
    .ancestor(
      of: find.byKey(bridge.control(field)),
      matching: find.byType(StarBridgeSwitch),
    )
    .first;

void _actualTitles(WidgetTester t, _Bridge bridge) {
  for (final field in bridge.fields) {
    final outer = _outer(bridge, field);
    final strings = AppStrings.of(t.element(outer));
    final text = strings.text(bridge.titleKey(field));
    expect(
      find.descendant(of: outer, matching: find.text(text)),
      findsOneWidget,
      reason: 'A reader label alone must not replace the visible $field title.',
    );
  }
}

void _visible(WidgetTester t, Finder target) {
  final rect = t.getRect(target);
  expect(rect.left, greaterThanOrEqualTo(-0.01));
  expect(rect.top, greaterThanOrEqualTo(-0.01));
  expect(rect.right, lessThanOrEqualTo(430.01));
  expect(rect.bottom, lessThanOrEqualTo(850.01));
}

Future<List<int>> _pixels(WidgetTester t) async => (await t.runAsync(() async {
  final boundary = t.renderObject<RenderRepaintBoundary>(find.byKey(_frame));
  final image = await boundary.toImage();
  try {
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    return bytes!.buffer.asUint8List().toList();
  } finally {
    image.dispose();
  }
}))!;

Future<void> _save(WidgetTester t, String name) async {
  final pixels = await _pixels(t);
  await t.runAsync(() async {
    final directory = Directory(_output);
    await directory.create(recursive: true);
    await File('${directory.path}/$name.png').writeAsBytes(pixels);
  });
}

Future<void> _close(
  WidgetTester t,
  _Bridge bridge,
  ScrollController scroll,
) async {
  await t.pumpWidget(const SizedBox.shrink());
  await t.runAsync(bridge.close);
  scroll.dispose();
}

Rect _relative(Rect child, Rect row) => child.shift(-row.topLeft);
void _sameRect(Rect actual, Rect expected) {
  expect(actual.left, closeTo(expected.left, .01));
  expect(actual.top, closeTo(expected.top, .01));
  expect(actual.width, closeTo(expected.width, .01));
  expect(actual.height, closeTo(expected.height, .01));
}

void main() {
  setUpAll(loadVisualFonts);
  for (final suite in InteractionSuite.values) {
    for (final locale in _locales) {
      for (final light in [false, true]) {
        for (final scale in [1.0, 2.0]) {
          final name =
              '${suite.name}-$locale-${light ? 'light' : 'dark'}-${scale.toInt()}';
          testWidgets(
            '$name real titles and bottom save feedback preserve scroll before deliberate user scroll',
            (t) async {
              size(t, const Size(430, 850));
              for (final kind in ['friend', 'game']) {
                final bridge = _Bridge(kind);
                final scroll = ScrollController();
                Widget app({bool reduce = false}) => _app(
                  bridge,
                  suite,
                  scroll,
                  locale: locale,
                  light: light,
                  scale: scale,
                  reduce: reduce,
                );
                try {
                  await t.pumpWidget(app());
                  await _ready(t, bridge);
                  _actualTitles(t, bridge);
                  // Start at the original bottom, then click its last row.
                  // Do not ensureVisible after insertion: first prove that
                  // the newly appended feedback has not auto-jumped the view.
                  scroll.jumpTo(scroll.position.maxScrollExtent);
                  await _frames(t, count: 2);
                  final row = find.descendant(
                    of: _outer(bridge, bridge.fields.last),
                    matching: find.byType(SuitePressable),
                  );
                  _visible(t, row);
                  final offsetBefore = scroll.offset;
                  await t.tap(row);
                  await _frames(t, count: 2);
                  expect(scroll.offset, closeTo(offsetBefore, .01));
                  expect(bridge.saves, hasLength(1));
                  expect(find.byType(HelpSupportWaiting), findsOneWidget);
                  expect(find.byType(LinearProgressIndicator), findsNothing);
                  _actualTitles(t, bridge);
                  // The footer legitimately lengthens the page. Explicitly
                  // model the user's additional scroll only after the no-jump
                  // check, retaining every field at its real text size.
                  final wait = find.byType(HelpSupportWaiting);
                  final overflow = t.getRect(wait).bottom - 838;
                  if (overflow > 0) {
                    scroll.jumpTo(
                      (scroll.offset + overflow)
                          .clamp(0.0, scroll.position.maxScrollExtent)
                          .toDouble(),
                    );
                    await _frames(t, count: 2);
                  }
                  _visible(t, row);
                  _visible(t, wait);
                  final waiting = t.widget<HelpSupportWaiting>(wait);
                  expect(waiting.source, InteractionSource.pointer);
                  expect(waiting.label, contains(' · '));
                  await _save(t, '$name-$kind-pending');
                  await t.pumpWidget(app(reduce: true));
                  await _frames(t);
                  expect(find.byType(SuiteProgressBar), findsNothing);
                  final staticPixels = await _pixels(t);
                  await t.pump(const Duration(milliseconds: 300));
                  expect(await _pixels(t), staticPixels);
                  expect(bridge.saves, hasLength(1));
                  await bridge.reply(
                    bridge.saves.single,
                    bridge.snapshot(save: bridge.saves.single),
                  );
                  await _frames(t);
                  expect(find.byType(HelpSupportWaiting), findsNothing);
                  expect(t.takeException(), isNull);
                } finally {
                  await _close(t, bridge, scroll);
                }
              }
            },
            timeout: _timeout,
            skip: !Platform.isWindows,
          );
        }
      }
    }

    testWidgets(
      '$suite theme-only real settings retain all actual Text titles without external scope',
      (t) async {
        size(t, const Size(430, 850));
        for (final kind in ['friend', 'game']) {
          final bridge = _Bridge(kind);
          final scroll = ScrollController();
          try {
            await t.pumpWidget(
              _app(
                bridge,
                suite,
                scroll,
                themeOnly: true,
                locale: const Locale('en'),
              ),
            );
            await _ready(t, bridge);
            _actualTitles(t, bridge);
            expect(
              find.byType(StarBridgeSwitch),
              findsNWidgets(bridge.fields.length),
            );
            expect(t.takeException(), isNull);
          } finally {
            await _close(t, bridge, scroll);
          }
        }
      },
      timeout: _timeout,
    );
  }

  for (final locale in _locales) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        '$locale $scale Standard native row and title geometry stays unchanged',
        (t) async {
          size(t, const Size(430, 850));
          for (final kind in ['friend', 'game']) {
            final bridge = _Bridge(kind);
            final scroll = ScrollController();
            try {
              await t.pumpWidget(
                _app(
                  bridge,
                  InteractionSuite.standard,
                  scroll,
                  locale: locale,
                  scale: scale,
                ),
              );
              await _ready(t, bridge);
              final measurements = <(String, Size, Rect)>[];
              for (final field in bridge.fields) {
                final target = find.byKey(bridge.control(field));
                expect(t.widget(target), isA<SwitchListTile>());
                final row = t.getRect(target);
                final strings = AppStrings.of(t.element(target));
                final text = strings.text(bridge.titleKey(field));
                final title = find.descendant(
                  of: target,
                  matching: find.text(text),
                );
                measurements.add((
                  text,
                  row.size,
                  _relative(t.getRect(title), row),
                ));
                if (kind == 'game') expect(row.width, closeTo(160, .01));
              }
              // Dispose the real Setting before rendering a pure native
              // reference. No second controller or hidden duplicate is used.
              for (final measurement in measurements) {
                final reference = Align(
                  alignment: Alignment.topLeft,
                  child: SizedBox(
                    width: measurement.$2.width,
                    child: SwitchListTile.adaptive(
                      key: const Key('3du-native-reference'),
                      contentPadding: EdgeInsets.zero,
                      title: Text(measurement.$1),
                      value: false,
                      onChanged: (_) {},
                    ),
                  ),
                );
                await t.pumpWidget(
                  _app(
                    bridge,
                    InteractionSuite.standard,
                    scroll,
                    locale: locale,
                    scale: scale,
                    reference: reference,
                  ),
                );
                await _frames(t, count: 2);
                final target = find.byKey(const Key('3du-native-reference'));
                final row = t.getRect(target);
                expect(row.width, closeTo(measurement.$2.width, .01));
                expect(row.height, closeTo(measurement.$2.height, .01));
                final title = find.descendant(
                  of: target,
                  matching: find.text(measurement.$1),
                );
                _sameRect(_relative(t.getRect(title), row), measurement.$3);
              }
              expect(t.takeException(), isNull);
            } finally {
              await _close(t, bridge, scroll);
            }
          }
        },
        timeout: _timeout,
      );
    }
  }
}
