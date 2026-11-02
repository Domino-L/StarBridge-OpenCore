import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/runtime/sharing_status_monitor.dart';
import 'package:starbridge_flutter/app/presence/manual_presence.dart';
import 'package:starbridge_flutter/app/shell/widgets/sharing_status_indicator.dart';
import 'package:starbridge_flutter/app/shell/widgets/sharing_status_notice.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_action_button.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_activation_origin.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_tooltip.dart';
import 'package:starbridge_flutter/design_system/tokens/starbridge_tokens.dart';
import 'package:starbridge_flutter/features/onboarding/connection_mode_controller.dart';
import 'package:starbridge_flutter/features/settings/local_privacy_controller.dart';
import 'package:starbridge_flutter/features/settings/privacy_publication_port.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../app/sharing_status_notice_test.dart' show NoticePrivacy;
import '../../features/onboarding/connection_mode_test.dart'
    show ModePort, modeFact;
import 'interaction_batch3do_test.dart'
    show exposedNodes, loadFonts, scopedApp, size;

Future<void> _frames(WidgetTester t, [int count = 2]) async {
  for (var i = 0; i < count; i++) {
    await t.pump(const Duration(milliseconds: 50));
  }
}

const _indicatorKey = Key('sharing-status-indicator');
const _retryKey = Key('sharing-status-retry');
const _settingsKey = Key('sharing-status-settings');
const _noticeKey = Key('sharing-status-notice');

Future<void> _mount(
  WidgetTester t,
  Widget child,
  InteractionSuite suite, {
  bool reduce = false,
  bool light = false,
  double width = 900,
}) async {
  await t.pumpWidget(
    scopedApp(
      SizedBox(width: width, child: child),
      suite,
      locale: const Locale('en'),
      reduce: reduce,
      light: light,
    ),
  );
  await _frames(t, 4);
}

Finder _adapter(Key key) => find.ancestor(
  of: find.byKey(key),
  matching: find.byType(StarBridgeActionButton),
);

FocusNode _focus(WidgetTester t, Finder target) => switch (t.widget(target)) {
  ButtonStyleButton b => b.focusNode!,
  SuitePressable b => b.focusNode!,
  _ => throw StateError('Missing public control owner'),
};

Future<void> _activate(
  WidgetTester t,
  Key key,
  String input,
  String label,
) async {
  final target = find.byKey(key);
  expect(target, findsOneWidget);
  if (input == 'pointer') {
    await t.tap(target);
  } else if (input == 'keyboard') {
    final focus = _focus(t, target);
    var tabs = 0;
    do {
      await t.sendKeyEvent(LogicalKeyboardKey.tab);
      await t.pump();
      tabs++;
    } while (FocusManager.instance.primaryFocus != focus && tabs < 48);
    expect(tabs, inInclusiveRange(1, 48));
    expect(FocusManager.instance.primaryFocus, same(focus));
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
  } else {
    final nodes = exposedNodes(t).where((node) {
      final data = node.getSemanticsData();
      return data.label == label && data.hasAction(SemanticsAction.tap);
    }).toList();
    expect(nodes, hasLength(1));
    t.binding.renderViews.single.owner!.semanticsOwner!.performAction(
      nodes.single.id,
      SemanticsAction.tap,
    );
  }
  await _frames(t);
}

InteractionSource _source(String input) =>
    input == 'pointer' ? InteractionSource.pointer : InteractionSource.keyboard;

class _HeldPrivacy extends NoticePrivacy {
  final gate = Completer<PrivacyPublicationView>();
  final applySources = <InteractionSource>[];
  final applyRevisions = <int?>[];
  @override
  Future<PrivacyPublicationView> publication(String action, {int? revision}) {
    if (action != 'apply') {
      return super.publication(action, revision: revision);
    }
    actions.add(action);
    applySources.add(currentStarBridgeActivationSource);
    applyRevisions.add(revision);
    return gate.future;
  }
}

class _Fixture {
  _Fixture({String state = 'failed', this.presence}) {
    port.state = state;
    controller = LocalPrivacyController(port);
    monitor = SharingStatusMonitor(controller: controller, presence: presence);
  }
  final port = _HeldPrivacy();
  final ManualPresenceController? presence;
  late final LocalPrivacyController controller;
  late final SharingStatusMonitor monitor;
  final opens = <InteractionSource>[];
  int providerCalls = 0;
  Widget content({bool compact = false}) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      SharingStatusNotice(
        status: monitor,
        onOpenSettings: () => opens.add(currentStarBridgeActivationSource),
        onRetry: () {
          providerCalls++;
          return monitor.canRetry ? () => unawaited(monitor.retry()) : null;
        },
      ),
      SharingStatusIndicator(
        monitor: monitor,
        compact: compact,
        onOpenSettings: () => opens.add(currentStarBridgeActivationSource),
      ),
    ],
  );
  Future<void> close(WidgetTester t) async {
    await t.pumpWidget(const SizedBox.shrink());
    monitor.dispose();
    controller.dispose();
    if (!port.gate.isCompleted) {
      port.gate.complete(const PrivacyPublicationView('applied', revision: 4));
    }
    await _frames(t);
    await t.runAsync(port.close);
  }
}

void _expectSingleAction(WidgetTester t, String label, {bool enabled = true}) {
  final nodes = exposedNodes(t)
      .where((n) => n.getSemanticsData().label == label)
      .toList();
  expect(nodes, hasLength(1));
  expect(
    nodes.single.getSemanticsData().hasAction(SemanticsAction.tap),
    enabled,
  );
}

void main() {
  setUpAll(loadFonts);
  testWidgets('sharing indicator actual Tab Enter retains keyboard source', (
    t,
  ) async {
    size(t, const Size(700, 850));
    final port = NoticePrivacy()..state = 'applied';
    final controller = LocalPrivacyController(port);
    final monitor = SharingStatusMonitor(controller: controller);
    final calls = <InteractionSource>[];
    try {
      await t.pumpWidget(
        scopedApp(
          SharingStatusIndicator(
            monitor: monitor,
            onOpenSettings: () => calls.add(currentStarBridgeActivationSource),
          ),
          InteractionSuite.scan,
          locale: const Locale('en'),
        ),
      );
      await _frames(t, 4);
      expect(monitor.indicator, SharingIndicatorState.sharing);
      await t.sendKeyEvent(LogicalKeyboardKey.tab);
      await t.pump();
      await t.sendKeyEvent(LogicalKeyboardKey.enter);
      await _frames(t);
      expect(calls, [InteractionSource.keyboard]);
      expect(port.writes, 0);
      expect(port.actions.every((action) => action == 'status'), isTrue);
      expect(t.takeException(), isNull);
    } finally {
      await t.pumpWidget(const SizedBox.shrink());
      monitor.dispose();
      controller.dispose();
      await t.runAsync(port.close);
    }
  }, timeout: const Timeout(Duration(seconds: 45)));

  for (final suite in InteractionSuite.values) {
    for (final input in ['pointer', 'keyboard', 'reader']) {
      for (final compact in [false, true]) {
        testWidgets(
          '$suite sharing indicator $input compact=$compact keeps full state',
          (t) async {
            size(t, const Size(1000, 850));
            final semantics = t.ensureSemantics();
            final f = _Fixture(state: 'applied');
            final saved = f.port.snapshot;
            try {
              await _mount(t, f.content(compact: compact), suite);
              expect(f.monitor.indicator, SharingIndicatorState.sharing);
              expect(find.byKey(_noticeKey), findsNothing);
              expect(
                find.text('Sharing'),
                compact ? findsNothing : findsOneWidget,
              );
              const label = 'Sharing · View sync and privacy';
              _expectSingleAction(t, label);
              final tooltip = t.widget<StarBridgeTooltip>(
                find.byType(StarBridgeTooltip),
              );
              expect(tooltip.message, label);
              expect(tooltip.excludeFromSemantics, isTrue);
              final adapter = t.widget<StarBridgeActionButton>(
                _adapter(_indicatorKey),
              );
              expect(adapter.kind, StarBridgeActionKind.quiet);
              expect(
                adapter.nativeStyle!.foregroundColor!.resolve({}),
                t.element(find.byKey(_indicatorKey)).tokens.colors.success,
              );
              await _activate(t, _indicatorKey, input, label);
              expect(f.opens, [_source(input)]);
              expect(f.port.snapshot, same(saved));
              expect(f.controller.revision, 4);
              expect(f.controller.dirty, isFalse);
              expect(f.port.writes, 0);
              expect(f.port.actions.every((a) => a == 'status'), isTrue);
              expect(t.takeException(), isNull);
            } finally {
              await f.close(t);
              semantics.dispose();
            }
          },
          timeout: const Timeout(Duration(seconds: 45)),
        );
      }

      testWidgets(
        '$suite sharing retry $input holds authority and original admission',
        (t) async {
          size(t, const Size(1000, 850));
          final semantics = t.ensureSemantics();
          final f = _Fixture();
          final saved = f.port.snapshot;
          try {
            await _mount(t, f.content(), suite);
            expect(f.monitor.value, 'failed');
            expect(f.monitor.canRetry, isTrue);
            _expectSingleAction(t, 'Retry now');
            await _activate(t, _settingsKey, input, 'View settings');
            expect(f.opens, [_source(input)]);
            expect(f.port.actions.where((a) => a == 'apply'), isEmpty);
            await _activate(t, _retryKey, input, 'Retry now');
            expect(f.port.applySources, [_source(input)]);
            expect(f.port.applyRevisions, [4]);
            expect(f.controller.publicationBusy, isTrue);
            expect(f.monitor.canRetry, isFalse);
            expect(f.controller.publicationView.state, 'failed');
            expect(f.monitor.indicator, SharingIndicatorState.unknown);
            expect(f.port.snapshot, same(saved));
            expect(f.port.writes, 0);
            expect(f.controller.dirty, isFalse);
            expect(f.port.gate.isCompleted, isFalse);
            expect(
              t.widget<StarBridgeActionButton>(_adapter(_retryKey)).onActivate,
              isNull,
            );
            _expectSingleAction(t, 'Retry now', enabled: false);
            // A real second pointer event at the disabled target cannot bypass
            // the provider's admission; no synthetic callback is invoked.
            await t.tapAt(t.getCenter(find.byKey(_retryKey)));
            await _frames(t);
            expect(f.port.applySources, hasLength(1));
            expect(find.byType(CircularProgressIndicator), findsNothing);
            expect(find.byType(SuiteBusyFrame), findsNothing);
            f.port.state = 'applied';
            f.port.gate.complete(
              const PrivacyPublicationView('applied', revision: 4),
            );
            await _frames(t, 4);
            expect(f.controller.publicationBusy, isFalse);
            expect(f.monitor.indicator, SharingIndicatorState.sharing);
            expect(find.byKey(_noticeKey), findsNothing);
            expect(f.port.actions.where((a) => a == 'apply'), hasLength(1));
            expect(f.port.snapshot, same(saved));
            expect(f.port.writes, 0);
            expect(t.takeException(), isNull);
          } finally {
            await f.close(t);
            semantics.dispose();
          }
        },
        timeout: const Timeout(Duration(seconds: 45)),
      );
    }

    testWidgets(
      '$suite retry provider is evaluated once only inside original gate',
      (t) async {
        size(t, const Size(1000, 1000));
        final semantics = t.ensureSemantics();
        final status = ValueNotifier<String?>(null);
        var providers = 0, retries = 0;
        try {
          final child = SharingStatusNotice(
            status: status,
            onOpenSettings: () {},
            onRetry: () {
              providers++;
              return () => retries++;
            },
          );
          await _mount(t, child, suite, width: 430);
          expect(providers, 0);
          expect(find.byKey(_noticeKey), findsNothing);
          for (final issue in [
            'waiting',
            'failed',
            'statusRead',
            'reconnecting',
            'network',
            'timeout',
            'server',
            'rateLimited',
            // Long-backoff failures keep consent and retry on their own; a
            // manual retry is still offered (sharing-auto-resume, CX-M04d).
            'permission',
            'contract',
            'service',
          ]) {
            final previous = providers;
            status.value = issue;
            await _frames(t);
            expect(
              providers,
              previous + 1,
              reason: 'Exactly one provider evaluation for $issue build.',
            );
            expect(find.byKey(_retryKey), findsOneWidget);
            status.value = issue;
            await _frames(t);
            expect(
              providers,
              previous + 1,
              reason: 'An unchanged persistent status is not re-announced.',
            );
          }
          for (final issue in [
            'identity',
            'identityPending',
            'consent',
            'paused',
            'signIn',
            'local',
            'withdrawal',
          ]) {
            final previous = providers;
            status.value = issue;
            await _frames(t);
            expect(providers, previous);
            expect(find.byKey(_retryKey), findsNothing);
            expect(find.byKey(_settingsKey), findsOneWidget);
          }
          expect(retries, 0);
          status.value = 'failed';
          await _frames(t);
          final beforeNull = providers;
          await _mount(
            t,
            SharingStatusNotice(
              status: status,
              onOpenSettings: () {},
              onRetry: () {
                providers++;
                return null;
              },
            ),
            suite,
            width: 430,
          );
          expect(providers, beforeNull + 1);
          expect(find.byKey(_retryKey), findsOneWidget);
          expect(
            t.widget<StarBridgeActionButton>(_adapter(_retryKey)).onActivate,
            isNull,
          );
          _expectSingleAction(t, 'Retry now', enabled: false);
          await _mount(
            t,
            SharingStatusNotice(status: status, onOpenSettings: () {}),
            suite,
            width: 430,
          );
          expect(find.byKey(_retryKey), findsNothing);
          expect(t.takeException(), isNull);
        } finally {
          await t.pumpWidget(const SizedBox.shrink());
          status.dispose();
          semantics.dispose();
        }
      },
      timeout: const Timeout(Duration(seconds: 45)),
    );

    testWidgets(
      '$suite actual monitor state receipts remain independent of draft and repeated reads',
      (t) async {
        size(t, const Size(1000, 1000));
        final semantics = t.ensureSemantics();
        final f = _Fixture();
        final saved = f.port.snapshot;
        try {
          await _mount(t, f.content(), suite);
          expect(f.monitor.value, 'failed');
          final previousProviders = f.providerCalls;
          await f.controller.refreshPublication();
          await _frames(t);
          expect(f.providerCalls, previousProviders);
          f.controller.edit(
            f.controller.draft!.copyWith(publicationEnabled: false),
          );
          await _frames(t);
          expect(f.monitor.value, 'failed');
          expect(f.controller.savedPublicationEnabled, isTrue);
          expect(
            f.monitor.canRetry,
            isFalse,
            reason: 'Draft cannot be published by a chrome retry.',
          );
          expect(
            t.widget<StarBridgeActionButton>(_adapter(_retryKey)).onActivate,
            isNull,
          );
          for (final pair in [
            ('applied', SharingIndicatorState.sharing),
            ('withdrawalPending', SharingIndicatorState.stopping),
            ('withdrawn', SharingIndicatorState.closed),
          ]) {
            f.port.state = pair.$1;
            await f.controller.refreshPublication();
            await _frames(t);
            expect(f.monitor.indicator, pair.$2);
            final control = t.widget<StarBridgeActionButton>(
              _adapter(_indicatorKey),
            );
            final colors = t.element(find.byKey(_indicatorKey)).tokens.colors;
            expect(
              control.nativeStyle!.foregroundColor!.resolve({}),
              switch (pair.$2) {
                SharingIndicatorState.sharing => colors.success,
                SharingIndicatorState.closed => colors.textSecondary,
                _ => colors.warning,
              },
            );
          }
          f.port.failStatus = true;
          await f.controller.refreshPublication();
          await _frames(t);
          expect(f.monitor.indicator, SharingIndicatorState.unknown);
          await f.controller.refreshPublication();
          await _frames(t);
          expect(f.monitor.value, 'statusRead');
          expect(find.text('Sharing status is unavailable'), findsOneWidget);
          expect(f.port.snapshot, same(saved));
          expect(f.port.writes, 0);
          expect(f.port.actions.every((a) => a == 'status'), isTrue);
          expect(find.byType(CircularProgressIndicator), findsNothing);
          expect(find.byType(SuiteBusyFrame), findsNothing);
          expect(t.takeException(), isNull);
        } finally {
          await f.close(t);
          semantics.dispose();
        }
      },
      timeout: const Timeout(Duration(seconds: 45)),
    );

    testWidgets(
      '$suite invisible and confirmed offline retain original chrome gates',
      (t) async {
        size(t, const Size(1000, 1000));
        final semantics = t.ensureSemantics();
        final modePort = ModePort();
        final mode = ConnectionModeController(modePort);
        final source = ValueNotifier(
          const ManualPresenceSnapshot(
            scope: 'fixture',
            confirmedMode: PresenceVisibility.online,
          ),
        );
        final presence = ManualPresenceController(
          source: source,
          connectionMode: mode,
        );
        final f = _Fixture(presence: presence);
        try {
          await t.runAsync(mode.refresh);
          await _mount(t, f.content(), suite);
          expect(f.monitor.value, 'failed');
          expect(find.byKey(_noticeKey), findsOneWidget);
          source.value = const ManualPresenceSnapshot(
            scope: 'fixture',
            confirmedMode: PresenceVisibility.invisible,
          );
          await _frames(t);
          expect(f.monitor.canRetry, isFalse);
          expect(find.byKey(_noticeKey), findsNothing);
          expect(
            find.byKey(_indicatorKey),
            findsNothing,
          ); // Unconfirmed state: no badge (2026-10-22).
          source.value = const ManualPresenceSnapshot(
            scope: 'fixture',
            confirmedMode: PresenceVisibility.online,
          );
          await _frames(t);
          expect(f.monitor.canRetry, isTrue);
          modePort.current = modeFact('offline');
          await t.runAsync(mode.refresh);
          await _frames(t);
          expect(f.monitor.isOffline, isTrue);
          expect(find.byKey(_noticeKey), findsNothing);
          expect(find.byKey(_indicatorKey), findsNothing);
          final reads = f.port.actions.length;
          await f.monitor
              .retry(); // Public negative admission, no UI is exposed.
          await t.pump(const Duration(seconds: 40));
          expect(f.port.actions.length, reads);
          expect(f.port.writes, 0);
          modePort.current = modeFact('online');
          await t.runAsync(mode.refresh);
          await _frames(t, 4);
          expect(f.monitor.isOffline, isFalse);
          expect(find.byKey(_noticeKey), findsOneWidget);
          expect(find.byKey(_indicatorKey), findsNothing);
          expect(t.takeException(), isNull);
        } finally {
          await f.close(t);
          presence.dispose();
          source.dispose();
          mode.dispose();
          await t.runAsync(modePort.events.close);
          semantics.dispose();
        }
      },
      timeout: const Timeout(Duration(seconds: 45)),
    );

    testWidgets(
      '$suite replacement and late receipt cannot call new chrome owner',
      (t) async {
        size(t, const Size(1000, 1000));
        final semantics = t.ensureSemantics();
        final old = _Fixture();
        final replacement = _Fixture(state: 'withdrawn');
        try {
          await _mount(t, old.content(), suite);
          await _activate(t, _retryKey, 'keyboard', 'Retry now');
          expect(old.controller.publicationBusy, isTrue);
          expect(old.port.applySources, [InteractionSource.keyboard]);
          await _mount(t, replacement.content(compact: true), suite);
          expect(replacement.monitor.indicator, SharingIndicatorState.closed);
          _expectSingleAction(t, 'Sharing off · View sync and privacy');
          old.port.state = 'applied';
          old.port.gate.complete(
            const PrivacyPublicationView('applied', revision: 4),
          );
          await _frames(t, 4);
          expect(old.monitor.indicator, SharingIndicatorState.sharing);
          expect(replacement.monitor.indicator, SharingIndicatorState.closed);
          expect(replacement.opens, isEmpty);
          expect(replacement.port.applySources, isEmpty);
          expect(old.port.writes, 0);
          expect(replacement.port.writes, 0);
          await _activate(
            t,
            _indicatorKey,
            'reader',
            'Sharing off · View sync and privacy',
          );
          expect(replacement.opens, [InteractionSource.keyboard]);
          expect(old.opens, isEmpty);
          await t.pumpWidget(const SizedBox.shrink());
          final oldRequests = old.port.actions.length;
          await _frames(t, 5);
          expect(old.port.actions.length, oldRequests);
          expect(t.takeException(), isNull);
        } finally {
          await old.close(t);
          await replacement.close(t);
          semantics.dispose();
        }
      },
      timeout: const Timeout(Duration(seconds: 45)),
    );

    testWidgets(
      '$suite live suite/theme/reduce leaves persistent status static',
      (t) async {
        size(t, const Size(1000, 1000));
        final semantics = t.ensureSemantics();
        final f = _Fixture(state: 'withdrawalPending');
        final saved = f.port.snapshot;
        try {
          await _mount(t, f.content(), suite, width: 430);
          expect(f.monitor.indicator, SharingIndicatorState.stopping);
          final label = 'Stopping sharing · View sync and privacy';
          _expectSingleAction(t, label);
          final controlState = t.state(_adapter(_indicatorKey));
          final next = InteractionSuite
              .values[(suite.index + 1) % InteractionSuite.values.length];
          await _mount(
            t,
            f.content(),
            next,
            width: 430,
            reduce: true,
            light: true,
          );
          expect(t.state(_adapter(_indicatorKey)), same(controlState));
          expect(f.monitor.indicator, SharingIndicatorState.stopping);
          _expectSingleAction(t, label);
          expect(
            Theme.of(t.element(find.byKey(_indicatorKey))).brightness,
            Brightness.light,
          );
          final local = find.byKey(_indicatorKey);
          expect(InteractionScope.of(t.element(local)).reduceMotion, isTrue);
          expect(find.byType(CircularProgressIndicator), findsNothing);
          expect(find.byType(SuiteBusyFrame), findsNothing);
          expect(find.byType(SuiteProgressBar), findsNothing);
          await _activate(t, _settingsKey, 'keyboard', 'View settings');
          expect(f.opens, [InteractionSource.keyboard]);
          expect(f.port.snapshot, same(saved));
          expect(f.port.writes, 0);
          expect(f.port.actions.every((a) => a == 'status'), isTrue);
          expect(t.takeException(), isNull);
        } finally {
          await f.close(t);
          semantics.dispose();
        }
      },
      timeout: const Timeout(Duration(seconds: 45)),
    );
  }
}
