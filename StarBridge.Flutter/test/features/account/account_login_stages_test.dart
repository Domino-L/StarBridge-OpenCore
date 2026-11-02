import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/bootstrap/starbridge_app.dart';
import 'package:starbridge_flutter/app/composition/app_composition.dart';
import 'package:starbridge_flutter/features/account/account_models.dart';
import 'package:starbridge_flutter/features/account/account_port.dart';
import 'package:starbridge_flutter/features/account/account_read_preparation.dart';
import 'package:starbridge_flutter/features/account/in_memory_account_adapter.dart';
import 'package:starbridge_flutter/platform/window/in_memory_window_chrome.dart';

// User request 2026-10-22: right after sign-in the account page still showed
// the offline cache, "compatibility not read" and "RSI identity cannot be
// confirmed". Sign-in runs in three stages instead: authorize, load the
// details the account page shows, then done.

final class _StagedLoginPort
    implements AccountPort, AccountReadPreparationPort {
  final source = InMemoryAccountAdapter(
    initial: const AccountHostSnapshot.signedOut(generation: 0),
  );
  final gate = Completer<void>();
  int pending = 0;

  @override
  bool get supportsStagedReads => true;
  @override
  bool get hasPendingReadPreparation => pending > 0;
  @override
  bool get shouldRetryReadPreparation => false;
  @override
  Future<AccountPortResult?> prepareNextRead({bool retry = false}) async {
    if (pending == 0) return null;
    await gate.future;
    pending--;
    return source.read();
  }

  @override
  void cancelReadPreparation() {}
  @override
  Stream<AccountInvalidation> get invalidations => source.invalidations;
  @override
  Future<AccountPortResult> read() => source.read();
  @override
  Future<AccountPortResult> execute(AccountPortCommand command) async {
    final result = await source.execute(command);
    // A completed sign-in leaves the account page's details to read.
    if (command is BeginAccountLogin) pending = 3;
    return result;
  }

  @override
  Future<void> close() => source.close();
}

void main() {
  testWidgets('sign-in finishes only after the account details are read', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 720);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final port = _StagedLoginPort();
    final composition = AppComposition.forTest(
      windowChrome: InMemoryWindowChrome(),
      accountPort: port,
    );
    await tester.pumpWidget(StarBridgeApp(composition: composition));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('account-command')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('account-menu-account-and-identity')),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('account-login')));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(port.pending, greaterThan(0));
    expect(
      find.text('授权成功，正在载入账号资料…'),
      findsOneWidget,
      reason: 'The dialog announced success before the details were read.',
    );
    expect(find.text('SCM 账号已连接。'), findsNothing);
    expect(find.byKey(const Key('account-login-stages')), findsOneWidget);

    port.gate.complete();
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(port.pending, 0);
    expect(find.text('SCM 账号已连接。'), findsOneWidget);
    expect(find.textContaining('完成登录'), findsOneWidget);
    await tester.tap(find.byKey(const Key('account-cancel-login')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('account-login-dialog')), findsNothing);
  });
}
