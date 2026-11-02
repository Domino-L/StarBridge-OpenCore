import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_switch.dart';
import 'package:starbridge_flutter/features/settings/direct_message_privacy_module.dart';
import 'package:starbridge_flutter/features/settings/direct_message_privacy_setting.dart';
import 'package:starbridge_flutter/features/settings/friend_request_privacy_module.dart';
import 'package:starbridge_flutter/features/settings/friend_request_privacy_setting.dart';
import 'package:starbridge_flutter/features/settings/help_support_action.dart';
import 'package:starbridge_flutter/features/settings/help_support_waiting.dart';
import 'package:starbridge_flutter/features/settings/recently_played_privacy_module.dart';
import 'package:starbridge_flutter/features/settings/recently_played_privacy_setting.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../_support/visual_output_dir.dart';
import 'interaction_batch3do_test.dart' show scopedApp, size;
import 'interaction_batch3dp_visual_test.dart' show loadVisualFonts;

const _frame = Key('3dt-visual-frame');
final _output = visualOutputDir('interaction_motion_batch3dt_20261016');
const _kinds = ['direct', 'friend', 'recent'];

Future<void> _frames(WidgetTester t, {int count = 4}) async {
  for (var i = 0; i < count; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

class _Gate {
  Completer<void>? reading;
  Completer<void>? writing;
  bool unavailable = false;
  bool saved = false;
  int reads = 0, writes = 0;

  Future<void> read() async {
    reads++;
    await reading?.future;
  }

  Future<void> write(bool next) async {
    writes++;
    await writing?.future;
    saved = next;
  }

  void release() {
    if (reading != null && !reading!.isCompleted) reading!.complete();
    if (writing != null && !writing!.isCompleted) writing!.complete();
  }
}

class _DirectPort implements DirectMessagePrivacyPort {
  _DirectPort(this.gate);
  final _Gate gate;
  @override
  Stream<void> get invalidations => const Stream.empty();
  @override
  Future<DirectMessagePrivacySnapshot> read() async {
    await gate.read();
    return gate.unavailable
        ? const DirectMessagePrivacySnapshot.unavailable(
            DirectMessagePrivacyFailure.readFailed,
          )
        : DirectMessagePrivacySnapshot.available(
            allowStrangerDirectMessages: gate.saved,
            updatedAt: null,
          );
  }

  @override
  Future<DirectMessagePrivacyWriteResult> save(bool next) async {
    await gate.write(next);
    return DirectMessagePrivacyWriteResult.completed(
      DirectMessagePrivacySnapshot.available(
        allowStrangerDirectMessages: next,
        updatedAt: null,
      ),
    );
  }

  @override
  Future<void> close() async {}
}

class _FriendPort implements FriendRequestPrivacyPort {
  _FriendPort(this.gate);
  final _Gate gate;
  @override
  Stream<void> get invalidations => const Stream.empty();
  @override
  Future<FriendRequestPrivacySnapshot> read() async {
    await gate.read();
    return gate.unavailable
        ? const FriendRequestPrivacySnapshot.unavailable(
            FriendRequestPrivacyFailure.readFailed,
          )
        : FriendRequestPrivacySnapshot.available(
            allowFriendRequests: gate.saved,
            updatedAt: null,
          );
  }

  @override
  Future<FriendRequestPrivacyWriteResult> save(bool next) async {
    await gate.write(next);
    return FriendRequestPrivacyWriteResult.completed(
      FriendRequestPrivacySnapshot.available(
        allowFriendRequests: next,
        updatedAt: null,
      ),
    );
  }

  @override
  Future<void> close() async {}
}

class _RecentPort implements RecentlyPlayedPrivacyPort {
  _RecentPort(this.gate);
  final _Gate gate;
  @override
  Stream<void> get invalidations => const Stream.empty();
  @override
  Future<RecentlyPlayedPrivacySnapshot> read() async {
    await gate.read();
    return gate.unavailable
        ? const RecentlyPlayedPrivacySnapshot.unavailable(
            RecentlyPlayedPrivacyFailure.readFailed,
          )
        : RecentlyPlayedPrivacySnapshot.available(
            enabled: gate.saved,
            enabledAt: null,
            disabledAt: null,
            revision: gate.saved ? 8 : 7,
          );
  }

  @override
  Future<RecentlyPlayedPrivacyWriteResult> save(bool next, int revision) async {
    expect(revision, 7);
    await gate.write(next);
    return RecentlyPlayedPrivacyWriteResult.completed(
      RecentlyPlayedPrivacySnapshot.available(
        enabled: next,
        enabledAt: null,
        disabledAt: null,
        revision: revision + 1,
      ),
    );
  }

  @override
  Future<void> close() async {}
}

class _Owners {
  _Owners() {
    direct = DirectMessagePrivacyModule(_DirectPort(gates[0]));
    friend = FriendRequestPrivacyModule(_FriendPort(gates[1]));
    recent = RecentlyPlayedPrivacyModule(_RecentPort(gates[2]));
  }
  final gates = [_Gate(), _Gate(), _Gate()];
  late final DirectMessagePrivacyModule direct;
  late final FriendRequestPrivacyModule friend;
  late final RecentlyPlayedPrivacyModule recent;

  List<Widget> get settings => [
    DirectMessagePrivacySetting(
      key: const Key('3dt-panel-direct'),
      module: direct,
    ),
    FriendRequestPrivacySetting(
      key: const Key('3dt-panel-friend'),
      module: friend,
    ),
    RecentlyPlayedPrivacySetting(
      key: const Key('3dt-panel-recent'),
      module: recent,
    ),
  ];
  List<Future<void>> initialize() => [
    direct.initialize(),
    friend.initialize(),
    recent.initialize(),
  ];
  Future<void> refresh() async {
    await Future.wait([direct.refresh(), friend.refresh(), recent.refresh()]);
  }

  void dispose() {
    direct.dispose();
    friend.dispose();
    recent.dispose();
  }
}

Finder _panel(String kind) => find.byKey(Key('3dt-panel-$kind'));
Finder _wait(String kind) => find.descendant(
  of: _panel(kind),
  matching: find.byType(HelpSupportWaiting),
);
Finder _retry(String kind) =>
    find.descendant(of: _panel(kind), matching: find.byType(HelpSupportAction));
Key _control(String kind) => Key(switch (kind) {
  'direct' => 'privacy-stranger-messages-authoritative',
  'friend' => 'privacy-friend-requests-authoritative',
  _ => 'privacy-recently-played-authoritative',
});

void _visible(WidgetTester t, Finder finder) {
  final rect = t.getRect(finder);
  expect(rect.left, greaterThanOrEqualTo(-0.01));
  expect(rect.top, greaterThanOrEqualTo(-0.01));
  expect(rect.right, lessThanOrEqualTo(430.01));
  expect(rect.bottom, lessThanOrEqualTo(850.01));
}

Future<void> _reveal(WidgetTester t, String kind) async {
  await Scrollable.ensureVisible(
    t.element(_panel(kind)),
    alignment: 0.12,
    duration: Duration.zero,
  );
  await _frames(t, count: 2);
  _visible(t, _panel(kind));
}

Future<List<int>> _pixels(WidgetTester t) async => (await t.runAsync(() async {
  final boundary = t.renderObject<RenderRepaintBoundary>(find.byKey(_frame));
  final image = await boundary.toImage();
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List().toList();
  } finally {
    image.dispose();
  }
}))!;

Future<void> _saveFrame(WidgetTester t, String name) async {
  final bytes = await _pixels(t);
  await t.runAsync(() async {
    final directory = Directory(_output);
    await directory.create(recursive: true);
    await File('${directory.path}/$name.png').writeAsBytes(bytes);
  });
}

void main() {
  setUpAll(loadVisualFonts);
  for (final suite in InteractionSuite.values) {
    for (final light in [false, true]) {
      for (final scale in [1.0, 2.0]) {
        final name =
            '${suite.name}-${light ? 'light' : 'dark'}-${scale.toInt()}';
        testWidgets(
          '$name three actual authoritative settings remain scrollable through read save and retry waits',
          (t) async {
            size(t, const Size(430, 850));
            final owners = _Owners();
            final scroll = ScrollController();
            Widget app({bool reduce = false}) => RepaintBoundary(
              key: _frame,
              child: scopedApp(
                Builder(
                  builder: (context) => MediaQuery(
                    data: MediaQuery.of(context)
                        .copyWith(textScaler: TextScaler.linear(scale)),
                    child: SizedBox.expand(
                      child: SingleChildScrollView(
                        controller: scroll,
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              '账户社交隐私',
                              style: Theme.of(context).textTheme.headlineSmall,
                            ),
                            const SizedBox(height: 20),
                            for (final setting in owners.settings) ...[
                              setting,
                              const Divider(height: 28),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                suite,
                light: light,
                reduce: reduce,
              ),
            );
            try {
              for (final gate in owners.gates) {
                gate.reading = Completer<void>();
              }
              final initialization = owners.initialize();
              await t.pumpWidget(app());
              await _frames(t, count: 2);
              expect(find.byType(HelpSupportWaiting), findsNWidgets(3));
              expect(find.byType(LinearProgressIndicator), findsNothing);
              expect(find.byType(StarBridgeSwitch), findsNothing);
              final labels = <String>[];
              for (final kind in _kinds) {
                await _reveal(t, kind);
                _visible(t, _wait(kind));
                labels.add(t.widget<HelpSupportWaiting>(_wait(kind)).label);
              }
              expect(labels.toSet(), hasLength(3));
              expect(labels.every((label) => label.contains(' · ')), isTrue);
              expect(labels[0], startsWith('允许非好友发起私信 · '));
              expect(labels[1], startsWith('允许非好友发送好友申请 · '));
              expect(labels[2], startsWith('允许共同参与者在“最近同玩”中找到我 · '));
              scroll.jumpTo(0);
              await _frames(t, count: 2);
              await _saveFrame(t, '$name-initial-read');
              for (final gate in owners.gates) {
                gate.reading!.complete();
                gate.reading = null;
              }
              await Future.wait(initialization);
              await _frames(t);
              for (final gate in owners.gates) {
                gate.writing = Completer<void>();
              }
              // All three independent owners really save concurrently. Do not
              // omit rows or fake their values merely to fit a narrow screen.
              for (final kind in _kinds) {
                final control = find.byKey(_control(kind));
                await t.ensureVisible(control);
                await _frames(t, count: 2);
                await t.tap(control);
                await _frames(t, count: 2);
              }
              expect(find.byType(HelpSupportWaiting), findsNWidgets(3));
              expect(owners.gates.map((gate) => gate.writes), [1, 1, 1]);
              for (final kind in _kinds) {
                final value = t.widget<StarBridgeSwitch>(
                  find
                      .ancestor(
                        of: find.byKey(_control(kind)),
                        matching: find.byType(StarBridgeSwitch),
                      )
                      .first,
                );
                expect(value.value, isFalse);
                expect(value.onChanged, isNull);
                await _reveal(t, kind);
                _visible(t, _wait(kind));
              }
              await _saveFrame(t, '$name-save-pending');
              await t.pumpWidget(app(reduce: true));
              await t.pump();
              await t.pump();
              expect(find.byType(SuiteProgressBar), findsNothing);
              final staticPixels = await _pixels(t);
              await t.pump(const Duration(milliseconds: 300));
              expect(
                await _pixels(t),
                staticPixels,
                reason: 'Live reduced motion stops the actual scene, not just a wait label.',
              );
              for (final gate in owners.gates) {
                gate.writing!.complete();
              }
              await _frames(t);
              await t.pumpWidget(app());
              await _frames(t);
              for (final gate in owners.gates) {
                gate.unavailable = true;
              }
              await owners.refresh();
              await _frames(t);
              for (final gate in owners.gates) {
                gate.reading = Completer<void>();
              }
              for (final kind in _kinds) {
                await _reveal(t, kind);
                _visible(t, _retry(kind));
                await t.tap(_retry(kind));
                await _frames(t, count: 2);
              }
              expect(find.byType(HelpSupportWaiting), findsNWidgets(3));
              for (final kind in _kinds) {
                await _reveal(t, kind);
                _visible(t, _retry(kind));
                _visible(t, _wait(kind));
              }
              expect(owners.gates.map((gate) => gate.reads), [3, 3, 3]);
              expect(owners.gates.map((gate) => gate.writes), [1, 1, 1]);
              await _saveFrame(t, '$name-read-retry');
              for (final gate in owners.gates) {
                gate.unavailable = false;
                gate.reading!.complete();
              }
              await _frames(t);
              expect(find.byType(HelpSupportWaiting), findsNothing);
              expect(t.takeException(), isNull);
            } finally {
              for (final gate in owners.gates) {
                gate.release();
              }
              await _frames(t, count: 2);
              await t.pumpWidget(const SizedBox.shrink());
              owners.dispose();
              scroll.dispose();
            }
          },
          timeout: const Timeout(Duration(seconds: 60)),
          skip: !Platform.isWindows,
        );
      }
    }
  }
}
