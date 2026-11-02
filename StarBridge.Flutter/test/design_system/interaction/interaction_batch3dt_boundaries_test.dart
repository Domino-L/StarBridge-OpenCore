import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_switch.dart';
import 'package:starbridge_flutter/features/settings/direct_message_privacy_module.dart';
import 'package:starbridge_flutter/features/settings/direct_message_privacy_setting.dart';
import 'package:starbridge_flutter/features/settings/friend_request_privacy_module.dart';
import 'package:starbridge_flutter/features/settings/friend_request_privacy_setting.dart';
import 'package:starbridge_flutter/features/settings/help_support_action.dart';
import 'package:starbridge_flutter/features/settings/help_support_waiting.dart';
import 'package:starbridge_flutter/features/settings/privacy_page_drafts.dart';
import 'package:starbridge_flutter/features/settings/recently_played_privacy_module.dart';
import 'package:starbridge_flutter/features/settings/recently_played_privacy_setting.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import 'interaction_batch3do_test.dart' as fixture;

const _timeout = Timeout(Duration(seconds: 45));

enum _Kind { direct, requests, recent }

enum _Outcome { success, rejected, unknown, conflict }

abstract interface class _Control {
  StreamController<void> get events;
  int get reads;
  int get revision;
  List<(bool, int?)> get writes;
  set outcome(_Outcome next);
  void pauseRead();
  void finishRead();
  VoidCallback takeReadCompletion();
  void unavailable();
  void pauseWrite();
  void finishWrite(bool value);
  void replace(bool value, int revision);
  Future<void> close();
}

/// Controlled domain transports, not a substitute module. All admission,
/// confirmed projections, epochs and queued reads use the three real modules.
abstract class _Port<S, R> implements _Control {
  _Port(
    this.makeSnapshot,
    this.completed,
    this.rejected,
    this.unknown,
    this.conflict,
    this.unavailableSnapshot,
  ) {
    current = makeSnapshot(true, revision);
  }
  final S Function(bool, int) makeSnapshot;
  final R Function(S) completed;
  final R rejected;
  final R unknown;
  final R conflict;
  final S unavailableSnapshot;
  late S current;
  @override
  final events = StreamController<void>.broadcast();
  @override
  int reads = 0;
  @override
  int revision = 7;
  @override
  final writes = <(bool, int?)>[];
  @override
  _Outcome outcome = _Outcome.success;
  Completer<S>? readGate;
  Completer<R>? writeGate;

  Future<S> readOwner() {
    reads++;
    return readGate?.future ?? Future.value(current);
  }

  Future<R> writeOwner(bool value, [int? expectedRevision]) async {
    writes.add((value, expectedRevision));
    if (expectedRevision != null && expectedRevision != revision) {
      return conflict;
    }
    if (writeGate != null) return writeGate!.future;
    if (outcome == _Outcome.rejected) return rejected;
    if (outcome == _Outcome.unknown) return unknown;
    if (outcome == _Outcome.conflict) return conflict;
    replace(value, revision + 1);
    return completed(current);
  }

  @override
  void pauseRead() => readGate = Completer<S>();
  @override
  void finishRead() {
    final gate = readGate;
    readGate = null;
    if (gate != null && !gate.isCompleted) gate.complete(current);
  }

  @override
  VoidCallback takeReadCompletion() {
    final gate = readGate!;
    final snapshot = current;
    readGate = null;
    return () {
      if (!gate.isCompleted) gate.complete(snapshot);
    };
  }

  @override
  void unavailable() => current = unavailableSnapshot;
  @override
  void pauseWrite() => writeGate = Completer<R>();
  @override
  void finishWrite(bool value) {
    final gate = writeGate;
    writeGate = null;
    replace(value, revision + 1);
    if (gate != null && !gate.isCompleted) gate.complete(completed(current));
  }

  @override
  void replace(bool value, int nextRevision) {
    revision = nextRevision;
    current = makeSnapshot(value, revision);
  }

  @override
  Future<void> close() async {
    finishRead();
    final gate = writeGate;
    writeGate = null;
    if (gate != null && !gate.isCompleted) gate.complete(rejected);
    await events.close();
  }
}

class _DirectPort
    extends _Port<DirectMessagePrivacySnapshot, DirectMessagePrivacyWriteResult>
    implements DirectMessagePrivacyPort {
  _DirectPort()
    : super(
        (value, revision) => DirectMessagePrivacySnapshot.available(
          allowStrangerDirectMessages: value,
          updatedAt: DateTime.utc(2026, 10, 16, 0, 0, revision),
        ),
        DirectMessagePrivacyWriteResult.completed,
        const DirectMessagePrivacyWriteResult.rejected(
          DirectMessagePrivacyFailure.writeFailed,
        ),
        const DirectMessagePrivacyWriteResult.unknown(),
        const DirectMessagePrivacyWriteResult.rejected(
          DirectMessagePrivacyFailure.invalidResponse,
        ),
        const DirectMessagePrivacySnapshot.unavailable(
          DirectMessagePrivacyFailure.readFailed,
        ),
      );
  @override
  Stream<void> get invalidations => events.stream;
  @override
  Future<DirectMessagePrivacySnapshot> read() => readOwner();
  @override
  Future<DirectMessagePrivacyWriteResult> save(bool value) => writeOwner(value);
}

class _RequestPort
    extends _Port<FriendRequestPrivacySnapshot, FriendRequestPrivacyWriteResult>
    implements FriendRequestPrivacyPort {
  _RequestPort()
    : super(
        (value, revision) => FriendRequestPrivacySnapshot.available(
          allowFriendRequests: value,
          updatedAt: DateTime.utc(2026, 10, 16, 0, 0, revision),
        ),
        FriendRequestPrivacyWriteResult.completed,
        const FriendRequestPrivacyWriteResult.rejected(
          FriendRequestPrivacyFailure.writeFailed,
        ),
        const FriendRequestPrivacyWriteResult.unknown(),
        const FriendRequestPrivacyWriteResult.rejected(
          FriendRequestPrivacyFailure.invalidResponse,
        ),
        const FriendRequestPrivacySnapshot.unavailable(
          FriendRequestPrivacyFailure.readFailed,
        ),
      );
  @override
  Stream<void> get invalidations => events.stream;
  @override
  Future<FriendRequestPrivacySnapshot> read() => readOwner();
  @override
  Future<FriendRequestPrivacyWriteResult> save(bool value) => writeOwner(value);
}

class _RecentPort
    extends
        _Port<RecentlyPlayedPrivacySnapshot, RecentlyPlayedPrivacyWriteResult>
    implements RecentlyPlayedPrivacyPort {
  _RecentPort()
    : super(
        (value, revision) => RecentlyPlayedPrivacySnapshot.available(
          enabled: value,
          enabledAt: value ? DateTime.utc(2026, 10, 16, 0, 0, revision) : null,
          disabledAt: value ? null : DateTime.utc(2026, 10, 16, 0, 0, revision),
          revision: revision,
        ),
        RecentlyPlayedPrivacyWriteResult.completed,
        const RecentlyPlayedPrivacyWriteResult.rejected(
          RecentlyPlayedPrivacyFailure.writeFailed,
        ),
        const RecentlyPlayedPrivacyWriteResult.unknown(),
        const RecentlyPlayedPrivacyWriteResult.rejected(
          RecentlyPlayedPrivacyFailure.writeConflict,
        ),
        const RecentlyPlayedPrivacySnapshot.unavailable(
          RecentlyPlayedPrivacyFailure.readFailed,
        ),
      );
  @override
  Stream<void> get invalidations => events.stream;
  @override
  Future<RecentlyPlayedPrivacySnapshot> read() => readOwner();
  @override
  Future<RecentlyPlayedPrivacyWriteResult> save(bool value, int revision) =>
      writeOwner(value, revision);
}

class _Owner {
  _Owner(this.kind) {
    switch (kind) {
      case _Kind.direct:
        final p = _DirectPort();
        port = p;
        module = DirectMessagePrivacyModule(p);
      case _Kind.requests:
        final p = _RequestPort();
        port = p;
        module = FriendRequestPrivacyModule(p);
      case _Kind.recent:
        final p = _RecentPort();
        port = p;
        module = RecentlyPlayedPrivacyModule(p);
    }
  }
  final _Kind kind;
  late final _Control port;
  late final Object module;
  Key get key => Key(switch (kind) {
    _Kind.direct => 'privacy-stranger-messages-authoritative',
    _Kind.requests => 'privacy-friend-requests-authoritative',
    _Kind.recent => 'privacy-recently-played-authoritative',
  });
  Widget get setting => switch (module) {
    DirectMessagePrivacyModule m => DirectMessagePrivacySetting(module: m),
    FriendRequestPrivacyModule m => FriendRequestPrivacySetting(module: m),
    RecentlyPlayedPrivacyModule m => RecentlyPlayedPrivacySetting(module: m),
    _ => throw StateError('unreachable owner'),
  };
  bool? get value => switch (module) {
    DirectMessagePrivacyModule m =>
      m.projection.value.snapshot.allowStrangerDirectMessages,
    FriendRequestPrivacyModule m =>
      m.projection.value.snapshot.allowFriendRequests,
    RecentlyPlayedPrivacyModule m => m.projection.value.snapshot.enabled,
    _ => null,
  };
  bool get canEdit => switch (module) {
    DirectMessagePrivacyModule m => m.projection.value.canEdit,
    FriendRequestPrivacyModule m => m.projection.value.canEdit,
    RecentlyPlayedPrivacyModule m => m.projection.value.canEdit,
    _ => false,
  };
  String? get failure => switch (module) {
    DirectMessagePrivacyModule m => m.projection.value.failure?.name,
    FriendRequestPrivacyModule m => m.projection.value.failure?.name,
    RecentlyPlayedPrivacyModule m => m.projection.value.failure?.name,
    _ => null,
  };
  int? get confirmedRevision => switch (module) {
    RecentlyPlayedPrivacyModule m => m.projection.value.snapshot.revision,
    _ => null,
  };
  Future<void> initialize() => switch (module) {
    DirectMessagePrivacyModule m => m.initialize(),
    FriendRequestPrivacyModule m => m.initialize(),
    RecentlyPlayedPrivacyModule m => m.initialize(),
    _ => throw StateError('unreachable owner'),
  };
  Future<void> refresh() => switch (module) {
    DirectMessagePrivacyModule m => m.refresh(),
    FriendRequestPrivacyModule m => m.refresh(),
    RecentlyPlayedPrivacyModule m => m.refresh(),
    _ => throw StateError('unreachable owner'),
  };
  Future<bool> save(bool next) => switch (module) {
    DirectMessagePrivacyModule m => m.save(next),
    FriendRequestPrivacyModule m => m.save(next),
    RecentlyPlayedPrivacyModule m => m.save(next),
    _ => throw StateError('unreachable owner'),
  };
  void dispose() {
    switch (module) {
      case DirectMessagePrivacyModule m:
        m.dispose();
      case FriendRequestPrivacyModule m:
        m.dispose();
      case RecentlyPlayedPrivacyModule m:
        m.dispose();
    }
  }
}

Future<void> _frames(WidgetTester t, {int count = 8}) async {
  for (var i = 0; i < count; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

Widget _app(_Owner owner, InteractionSuite suite, {PrivacyPageDrafts? drafts}) {
  Widget child = SizedBox(width: 560, child: owner.setting);
  if (drafts != null) child = PrivacyDraftScope(drafts: drafts, child: child);
  return fixture.scopedApp(child, suite);
}

StarBridgeSwitch _switch(WidgetTester t, _Owner owner) {
  final target = find.byKey(owner.key);
  if (t.widget(target) is StarBridgeSwitch) {
    return t.widget<StarBridgeSwitch>(target);
  }
  return t.widget<StarBridgeSwitch>(
    find.ancestor(of: target, matching: find.byType(StarBridgeSwitch)).first,
  );
}

Future<void> _tap(WidgetTester t, _Owner owner) async {
  await t.tap(find.byKey(owner.key));
  await t.pump();
}

Future<void> _keyboard(WidgetTester t, _Owner owner) async {
  final target = find.byKey(owner.key);
  final focus = switch (t.widget(target)) {
    Switch widget => widget.focusNode!,
    SuiteSwitch widget => widget.focusNode!,
    _ => throw StateError('Missing actual switch focus target'),
  };
  focus.requestFocus();
  await t.pump();
  await t.sendKeyEvent(LogicalKeyboardKey.enter);
}

Future<void> _mount(
  WidgetTester t,
  _Owner owner,
  InteractionSuite suite, {
  PrivacyPageDrafts? drafts,
}) async {
  fixture.size(t, const Size(1000, 850));
  await owner.initialize();
  await t.pumpWidget(_app(owner, suite, drafts: drafts));
  await _frames(t);
  expect(owner.value, isTrue);
  expect(owner.port.reads, 1);
  expect(owner.port.writes, isEmpty);
}

Future<void> _unmount(WidgetTester t) async {
  await t.pumpWidget(const SizedBox.shrink());
  await _frames(t, count: 2);
}

void main() {
  setUpAll(fixture.loadFonts);
  for (final suite in InteractionSuite.values) {
    for (final kind in _Kind.values) {
      testWidgets(
        '$suite $kind same frame consecutive saves renew phase and source',
        (t) async {
          final owner = _Owner(kind);
          try {
            await _mount(t, owner, suite);
            owner.port.pauseWrite();
            await _keyboard(t, owner);
            await _frames(t, count: 2);
            final firstWait = t.widget<HelpSupportWaiting>(
              find.byType(HelpSupportWaiting),
            );
            expect(firstWait.source, InteractionSource.keyboard);
            expect(find.byType(SuiteProgressBar), findsNothing);
            expect(owner.port.writes, hasLength(1));

            // Let the real module publish its successful receipt and finish
            // the first command, but deliberately render no intermediate idle
            // frame. The existing child widget still has saving == true.
            owner.port.finishWrite(false);
            for (var i = 0; i < 8; i++) {
              await Future<void>.value();
            }
            expect(owner.canEdit, isTrue);
            expect(owner.value, isFalse);
            owner.port.pauseWrite();
            final second = owner.save(true);
            expect(owner.port.writes, hasLength(2));
            expect(owner.canEdit, isFalse);
            await t.pump();
            final secondWait = t.widget<HelpSupportWaiting>(
              find.byType(HelpSupportWaiting),
            );
            expect(secondWait.source, InteractionSource.programmatic);
            expect(secondWait.key, isNot(firstWait.key));
            expect(find.byType(SuiteProgressBar), findsOneWidget);
            expect(owner.value, isFalse);
            owner.port.finishWrite(true);
            expect(await second, isTrue);
            await _frames(t);
            expect(owner.value, isTrue);
            expect(owner.port.writes, hasLength(2));
            expect(owner.port.reads, 1);
            expect(find.byType(HelpSupportWaiting), findsNothing);
            expect(t.takeException(), isNull);
          } finally {
            await _unmount(t);
            owner.dispose();
          }
        },
        timeout: _timeout,
      );

      testWidgets(
        '$suite $kind same frame identity invalidation retires old explicit retry without clearing newer wait',
        (t) async {
          fixture.size(t, const Size(1000, 850));
          final owner = _Owner(kind);
          VoidCallback? oldCompletion;
          try {
            owner.port.unavailable();
            await owner.initialize();
            await t.pumpWidget(_app(owner, suite));
            await _frames(t);
            expect(owner.value, isNull);
            expect(owner.port.reads, 1);
            owner.port.pauseRead();
            await t.tap(find.byType(HelpSupportAction));
            await t.pump();
            await _frames(t, count: 2);
            expect(find.byType(HelpSupportWaiting), findsOneWidget);
            expect(owner.port.reads, 2);
            oldCompletion = owner.port.takeReadCompletion();

            // Drain the real broadcast invalidation and its immediately ready
            // read through microtasks only. The UI never builds loading here.
            owner.port.events.add(null);
            for (var i = 0; i < 8; i++) {
              await Future<void>.value();
            }
            expect(owner.port.reads, 3);
            expect(owner.value, isNull);
            await t.pump();
            expect(find.byType(HelpSupportWaiting), findsNothing);

            owner.port.pauseRead();
            final retry = t.widget<HelpSupportAction>(
              find.byType(HelpSupportAction),
            );
            await fixture.act(
              t,
              find.byKey(retry.controlKey),
              'keyboard',
              (retry.child as Text).data!,
            );
            await _frames(t, count: 2);
            expect(owner.port.reads, 4);
            final newWait = t.widget<HelpSupportWaiting>(
              find.byType(HelpSupportWaiting),
            );
            expect(newWait.source, InteractionSource.keyboard);
            oldCompletion();
            await _frames(t, count: 2);
            expect(find.byType(HelpSupportWaiting), findsOneWidget);
            final retained = t.widget<HelpSupportWaiting>(
              find.byType(HelpSupportWaiting),
            );
            expect(retained.key, newWait.key);
            expect(retained.source, InteractionSource.keyboard);
            expect(owner.port.writes, isEmpty);
            owner.port.finishRead();
            await _frames(t);
            expect(find.byType(HelpSupportWaiting), findsNothing);
            expect(owner.port.writes, isEmpty);
            expect(owner.port.reads, 4);
            expect(t.takeException(), isNull);
          } finally {
            oldCompletion?.call();
            owner.port.finishRead();
            await _unmount(t);
            owner.dispose();
          }
        },
        timeout: _timeout,
      );

      testWidgets(
        '$suite $kind rejected and unknown replies retain confirmed values without implicit mutation retry',
        (t) async {
          for (final result in [_Outcome.rejected, _Outcome.unknown]) {
            final owner = _Owner(kind);
            try {
              await _mount(t, owner, suite);
              owner.port.outcome = result;
              await _tap(t, owner);
              await _frames(t);
              expect(owner.port.writes, hasLength(1));
              expect(owner.port.writes.single.$1, isFalse);
              expect(owner.value, isTrue);
              expect(_switch(t, owner).value, isTrue);
              expect(owner.canEdit, isTrue);
              expect(
                owner.failure,
                result == _Outcome.unknown ? 'outcomeUnknown' : 'writeFailed',
              );
              expect(owner.port.reads, 1);
              await owner.refresh();
              await _frames(t);
              expect(owner.port.reads, 2);
              expect(owner.port.writes, hasLength(1));
              expect(owner.value, isTrue);
              expect(owner.failure, isNull);
              expect(t.takeException(), isNull);
            } finally {
              await _unmount(t);
              owner.dispose();
            }
          }
        },
        timeout: _timeout,
      );

      testWidgets(
        '$suite $kind background refresh keeps editable unified draft and writes only on explicit save',
        (t) async {
          final owner = _Owner(kind);
          final drafts = PrivacyPageDrafts();
          try {
            await _mount(t, owner, suite, drafts: drafts);
            owner.port.pauseRead();
            final refresh = owner.refresh();
            await _frames(t, count: 2);
            expect(owner.canEdit, isTrue);
            expect(_switch(t, owner).onChanged, isNotNull);
            await _tap(t, owner);
            await _frames(t, count: 2);
            expect(owner.port.writes, isEmpty);
            expect(drafts.dirty, isTrue);
            expect(_switch(t, owner).value, isFalse);
            expect(owner.value, isTrue);
            owner.port.finishRead();
            await refresh;
            await _frames(t);
            expect(drafts.dirty, isTrue);
            expect(_switch(t, owner).value, isFalse);
            expect(owner.port.writes, isEmpty);
            expect(await drafts.save(), isTrue);
            await _frames(t);
            expect(owner.port.writes, hasLength(1));
            expect(owner.value, isFalse);
            expect(drafts.dirty, isFalse);
            expect(t.takeException(), isNull);
          } finally {
            owner.port.finishRead();
            await _unmount(t);
            drafts.dispose();
            owner.dispose();
          }
        },
        timeout: _timeout,
      );

      testWidgets(
        '$suite $kind pending owner rejects duplicate callbacks and keeps queued read and invalidation semantics',
        (t) async {
          final owner = _Owner(kind);
          try {
            await _mount(t, owner, suite);
            owner.port.pauseWrite();
            final old = _switch(t, owner).onChanged!;
            await _tap(t, owner);
            await _frames(t, count: 2);
            expect(_switch(t, owner).onChanged, isNull);
            old(false);
            await owner.refresh();
            await owner.refresh();
            await _frames(t, count: 2);
            expect(owner.port.writes, hasLength(1));
            expect(owner.port.reads, 1);
            owner.port.finishWrite(false);
            await _frames(t);
            expect(owner.value, isFalse);
            expect(owner.port.reads, 2);
            expect(owner.port.writes, hasLength(1));

            owner.port.pauseWrite();
            await _tap(t, owner);
            await _frames(t, count: 2);
            expect(owner.port.writes, hasLength(2));
            owner.port.replace(false, 41);
            owner.port.events.add(null);
            await _frames(t);
            expect(owner.value, isFalse);
            expect(owner.port.reads, 3);
            owner.port.finishWrite(true);
            await _frames(t);
            expect(owner.value, isFalse);
            if (kind == _Kind.recent) expect(owner.confirmedRevision, 41);
            expect(owner.port.writes, hasLength(2));
            expect(t.takeException(), isNull);
          } finally {
            await _unmount(t);
            owner.dispose();
          }
        },
        timeout: _timeout,
      );

      testWidgets(
        '$suite $kind replacement isolates old future and unmount does not cancel original owner receipt',
        (t) async {
          final old = _Owner(kind);
          final next = _Owner(kind);
          try {
            await _mount(t, old, suite);
            old.port.pauseWrite();
            await _tap(t, old);
            await _frames(t, count: 2);
            expect(find.byType(HelpSupportWaiting), findsOneWidget);
            await next.initialize();
            await t.pumpWidget(_app(next, suite));
            await _frames(t, count: 2);
            expect(_switch(t, next).value, isTrue);
            expect(find.byType(HelpSupportWaiting), findsNothing);
            next.port.pauseWrite();
            await _keyboard(t, next);
            await _frames(t, count: 2);
            final wait = t.widget<HelpSupportWaiting>(
              find.byType(HelpSupportWaiting),
            );
            expect(wait.source, InteractionSource.keyboard);
            old.port.finishWrite(false);
            await _frames(t, count: 2);
            expect(old.value, isFalse);
            expect(next.value, isTrue);
            expect(find.byType(HelpSupportWaiting), findsOneWidget);
            expect(
              t.widget<HelpSupportWaiting>(find.byType(HelpSupportWaiting)).key,
              wait.key,
            );
            expect(
              t
                  .widget<HelpSupportWaiting>(find.byType(HelpSupportWaiting))
                  .source,
              InteractionSource.keyboard,
            );
            await _unmount(t);
            next.port.finishWrite(false);
            await _frames(t);
            expect(next.value, isFalse);
            expect(old.port.writes, hasLength(1));
            expect(next.port.writes, hasLength(1));
            expect(t.takeException(), isNull);
          } finally {
            await _unmount(t);
            old.dispose();
            next.dispose();
          }
        },
        timeout: _timeout,
      );

      testWidgets(
        '$suite $kind later external save never inherits expired keyboard source',
        (t) async {
          final owner = _Owner(kind);
          try {
            await _mount(t, owner, suite);
            owner.port.pauseWrite();
            await _keyboard(t, owner);
            await _frames(t, count: 2);
            expect(
              t
                  .widget<HelpSupportWaiting>(find.byType(HelpSupportWaiting))
                  .source,
              InteractionSource.keyboard,
            );
            owner.port.finishWrite(false);
            await _frames(t);
            expect(find.byType(HelpSupportWaiting), findsNothing);
            owner.port.pauseWrite();
            final external = owner.save(true);
            await _frames(t, count: 2);
            expect(
              t
                  .widget<HelpSupportWaiting>(find.byType(HelpSupportWaiting))
                  .source,
              InteractionSource.programmatic,
            );
            expect(find.byType(SuiteProgressBar), findsOneWidget);
            owner.port.finishWrite(true);
            expect(await external, isTrue);
            await _frames(t);
            expect(owner.value, isTrue);
            expect(owner.port.writes, hasLength(2));
            expect(t.takeException(), isNull);
          } finally {
            await _unmount(t);
            owner.dispose();
          }
        },
        timeout: _timeout,
      );
    }

    testWidgets(
      '$suite recently played conflict retains revision until explicit refresh and never retries write',
      (t) async {
        final owner = _Owner(_Kind.recent);
        try {
          await _mount(t, owner, suite);
          owner.port.outcome = _Outcome.conflict;
          await _tap(t, owner);
          await _frames(t);
          expect(owner.failure, 'writeConflict');
          expect(owner.confirmedRevision, 7);
          expect(owner.port.writes.single, (false, 7));
          expect(owner.port.reads, 1);
          expect(owner.value, isTrue);
          owner.port.replace(false, 31);
          await owner.refresh();
          await _frames(t);
          expect(owner.confirmedRevision, 31);
          expect(owner.value, isFalse);
          expect(owner.failure, isNull);
          expect(owner.port.writes, hasLength(1));
          expect(owner.port.reads, 2);
          expect(t.takeException(), isNull);
        } finally {
          await _unmount(t);
          owner.dispose();
        }
      },
      timeout: _timeout,
    );
  }
}
