import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/preferences/app_preferences.dart';
import 'package:starbridge_flutter/design_system/style_registry.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/account/account_safety.dart';
import 'package:starbridge_flutter/features/account/account_safety_dialog.dart';

final _now = DateTime.utc(2026, 9, 13);
final _snapshot = AccountSafetySnapshot(const [], const [], const [], _now);
void main() {
  testWidgets('appeal editor requires explicit input and submission', (
    tester,
  ) async {
    final port = _Port()
      ..load = () async => AccountSafetySnapshot(
        [
          AccountSafetyRecord(
            id: 'sanction',
            type: 'warning',
            text: 'Test action',
            createdAt: _now,
          ),
        ],
        const [],
        const [],
        _now,
      );
    final pending = Completer<AccountAppealOutcome>();
    port.send = () => pending.future;
    final controller = AccountSafetyController(port);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildStarBridgeTheme(
          StyleRegistry()
              .resolve(
                AppPreferences.defaults.designStyleId,
                AppearanceMode.dark,
              )
              .tokens,
          const Locale('en'),
        ),
        home: AccountSafetyDialog(controller: controller),
      ),
    );
    await tester.pumpAndSettle();
    expect(port.submits, 0);
    await tester.tap(find.text('Submit appeal'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    await tester.enterText(find.byType(TextField), '   ');
    await tester.pump();
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
    expect(port.submits, 0);
    await tester.tap(find.text('Submit appeal'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextField),
      'Please review this action.',
    );
    await tester.pump();
    await tester.tap(find.byType(FilledButton));
    await tester.pump();
    expect(port.submits, 1);
    expect(find.text('Submitting…'), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
    pending.complete(AccountAppealOutcome.submitted);
    await tester.pumpAndSettle();
    expect(find.text('Appeal submitted'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(find.text('Submit appeal'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets(
    'explicit submission is serialized and uncertain outcomes are never replayed',
    (tester) async {
      final port = _Port()
        ..load = () async => AccountSafetySnapshot(
          [
            AccountSafetyRecord(
              id: 'sanction',
              type: 'warning',
              text: 'reason',
              createdAt: _now,
            ),
          ],
          const [],
          const [],
          _now,
        );
      final pending = Completer<AccountAppealOutcome>();
      port.send = () => pending.future;
      final controller = AccountSafetyController(port);
      await tester.pump();
      expect(port.submits, 0);
      final first = controller.submit(
        'sanction',
        'explanation',
        controller.identityRevision,
      );
      await controller.submit(
        'sanction',
        'explanation',
        controller.identityRevision,
      );
      await tester.pump(const Duration(seconds: 30));
      expect(port.submits, 1);
      expect(port.reads, 1);
      pending.complete(AccountAppealOutcome.unknown);
      await first;
      await tester.pump(const Duration(seconds: 30));
      await controller.submit(
        'sanction',
        'explanation',
        controller.identityRevision,
      );
      expect(port.submits, 1);
      expect(
        controller.appealOutcomes['sanction'],
        AccountAppealOutcome.unknown,
      );
      expect(port.requestIds.single.length, 32);
      controller.dispose();
    },
  );

  testWidgets(
    'draft from previous identity cannot submit after account switch',
    (tester) async {
      final port = _Port()
        ..load = () async => AccountSafetySnapshot(
          [
            AccountSafetyRecord(
              id: 'sanction',
              type: 'warning',
              text: 'reason',
              createdAt: _now,
            ),
          ],
          const [],
          const [],
          _now,
        );
      final controller = AccountSafetyController(port);
      await tester.pump();
      final identity = controller.identityRevision;
      port.changes.add(null);
      await tester.pump();
      await controller.submit('sanction', 'explanation', identity);
      expect(port.submits, 0);
      controller.dispose();
    },
  );
  test('invalid and incomplete data never become a healthy account', () {
    for (final body in <Map<String, Object?>>[
      {},
      {'schemaVersion': 1},
      {
        'schemaVersion': 1,
        'sanctions': [],
        'appeals': [],
        'restrictions': [12],
        'updatedAt': _now.toIso8601String(),
      },
    ]) {
      expect(() => AccountSafetySnapshot.parse(body), throwsFormatException);
    }
    expect(
      AccountSafetySnapshot.parse({
        'schemaVersion': 1,
        'sanctions': [],
        'appeals': [],
        'restrictions': [],
        'updatedAt': _now.toIso8601String(),
      }).updatedAt,
      _now,
    );
  });

  testWidgets(
    'background refresh retains facts on temporary failure and recovers',
    (tester) async {
      final port = _Port();
      final controller = AccountSafetyController(port);
      await tester.pump();
      expect(controller.snapshot, same(_snapshot));
      port.load = () async =>
          throw const AccountSafetyException(AccountSafetyFailure.connection);
      await tester.pump(const Duration(seconds: 30));
      expect(controller.snapshot, same(_snapshot));
      expect(controller.failure, AccountSafetyFailure.connection);
      port.load = () async => _snapshot;
      await tester.pump(const Duration(seconds: 30));
      expect(controller.failure, isNull);
      expect(port.reads, 3);
      controller.dispose();
    },
  );

  testWidgets(
    'account invalidation clears cached facts and rejects a late response',
    (tester) async {
      final port = _Port();
      final controller = AccountSafetyController(port);
      await tester.pump();
      final pending = Completer<AccountSafetySnapshot>();
      port.load = () => pending.future;
      unawaited(controller.refresh());
      port.load = () async =>
          throw const AccountSafetyException(AccountSafetyFailure.signedOut);
      port.changes.add(null);
      await tester.pump();
      expect(controller.snapshot, isNull);
      pending.complete(_snapshot);
      await tester.pump();
      expect(controller.snapshot, isNull);
      expect(controller.failure, AccountSafetyFailure.signedOut);
      controller.dispose();
    },
  );

  testWidgets(
    'dialog shows loading then empty facts and survives narrow large text',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(420, 620));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final pending = Completer<AccountSafetySnapshot>();
      final port = _Port()..load = () => pending.future;
      final controller = AccountSafetyController(port);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildStarBridgeTheme(
            StyleRegistry()
                .resolve(
                  AppPreferences.defaults.designStyleId,
                  AppearanceMode.dark,
                )
                .tokens,
            const Locale('en'),
          ),
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(420, 620),
              textScaler: TextScaler.linear(1.5),
            ),
            child: AccountSafetyDialog(controller: controller),
          ),
        ),
      );
      expect(find.text('Loading account status…'), findsOneWidget);
      expect(find.text('No current feature restrictions'), findsNothing);
      pending.complete(_snapshot);
      await tester.pumpAndSettle();
      expect(find.text('No current feature restrictions'), findsOneWidget);
      expect(find.text('No records'), findsNWidgets(2));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );
}

class _Port implements AccountSafetyPort {
  int submits = 0;
  final requestIds = <String>[];
  Future<AccountAppealOutcome> Function() send = () async =>
      AccountAppealOutcome.submitted;
  @override
  bool get canSubmit => true;
  @override
  Future<AccountAppealOutcome> submit(
    String id,
    String details,
    String requestId,
  ) async {
    submits++;
    requestIds.add(requestId);
    return send();
  }

  final changes = StreamController<void>.broadcast();
  Future<AccountSafetySnapshot> Function() load = () async => _snapshot;
  int reads = 0;
  @override
  Stream<void> get invalidations => changes.stream;
  @override
  Future<AccountSafetySnapshot> read() {
    reads++;
    return load();
  }

  @override
  void dispose() {
    unawaited(changes.close());
  }
}
