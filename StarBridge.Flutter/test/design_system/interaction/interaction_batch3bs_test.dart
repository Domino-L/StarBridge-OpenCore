import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';
import 'package:starbridge_flutter/design_system/brand/scm_success_motion.dart';
import 'package:starbridge_flutter/design_system/icons/starbridge_icon.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_dialog.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_field_frame.dart';
import 'package:starbridge_flutter/features/account/account_models.dart';
import 'package:starbridge_flutter/features/account/account_module.dart';
import 'package:starbridge_flutter/features/account/account_page.dart';
import 'package:starbridge_flutter/features/account/account_port.dart';

import 'interaction_batch3bg_test.dart' show activate;
import 'interaction_batch3bq_test.dart' show button, clean;
import 'interaction_batch3br_test.dart' show PreferencesPort, mount;
import 'interaction_batch3i_test.dart' show scopedApp;

class CompatibilityPort extends PreferencesPort {
  Completer<AccountPortResult>? cancellation;
  AccountHostSnapshot? replacement;
  @override
  Future<AccountPortResult> read() {
    if (replacement case final snapshot?) {
      reads++;
      return Future.value(AccountPortResult.completed(snapshot));
    }
    return super.read();
  }

  @override
  Future<AccountPortResult> execute(AccountPortCommand command) {
    if (command is CancelCompatibilityOperation && cancellation != null) {
      commands.add(command);
      return cancellation!.future;
    }
    return super.execute(command);
  }
}

Future<void> cleanup(
  WidgetTester t,
  AccountModule m,
  CompatibilityPort p,
) async {
  if (p.held != null && !p.held!.isCompleted) {
    p.held!.complete(AccountPortResult.cancelled(p.delegate.snapshot));
  }
  if (p.cancellation != null && !p.cancellation!.isCompleted) {
    p.cancellation!.complete(AccountPortResult.cancelled(p.delegate.snapshot));
  }
  await clean(t, m, p);
}

Future<void> hit(WidgetTester t, String source, String key) async {
  final finder = find.byKey(Key(key));
  await t.ensureVisible(finder);
  if (source == 'keyboard' && key == 'account-legacy-dialog-close') {
    Focus.of(
      t.element(
        find
            .descendant(of: finder, matching: find.byType(StarBridgeIcon))
            .first,
      ),
    ).requestFocus();
    await t.pump();
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pump();
    await t.pump();
  } else {
    await activate(t, source, Key(key));
  }
}

Future<void> openLink(
  WidgetTester t,
  AccountModule m,
  CompatibilityPort p,
  InteractionSuite suite,
  String source,
) async {
  await mount(t, m, suite);
  expect(button(t, 'account-compatibility-link').onActivate, isNotNull);
  expect(find.byKey(const Key('account-compatibility-create')), findsNothing);
  await hit(t, source, 'account-compatibility-link');
  await t.pumpAndSettle();
  expect(
    ModalRoute.of(t.element(find.byKey(const Key('account-legacy-name')))),
    isA<StarBridgeDialogRoute<LegacyAccountCredential>>(),
  );
  expect(find.byType(StarBridgeFieldFrame), findsNWidgets(2));
  expect(p.commands, isEmpty);
}

Future<void> submit(WidgetTester t, String source) async {
  await t.enterText(
    find.byKey(const Key('account-legacy-name')),
    '  legacy-demo  ',
  );
  await t.enterText(
    find.byKey(const Key('account-legacy-password')),
    'unit-test-only',
  );
  await hit(t, source, 'account-legacy-submit');
  await t.pump(const Duration(milliseconds: 400));
  await t.pump();
}

void main() {
  setUpAll(ScmSuccessMotion.verifyArtwork);
  for (final suite in InteractionSuite.values) {
    testWidgets(
      '$suite refused cancellation allows fresh credentials and rejects the old reply',
      (t) async {
        final p = CompatibilityPort(), m = createAccountModule(p);
        try {
          await m.initialize();
          await openLink(t, m, p, suite, 'pointer');
          p.heldType = LinkLegacyAccount;
          p.held = Completer<AccountPortResult>();
          final old = p.held!;
          await submit(t, 'pointer');
          p.cancellation = Completer<AccountPortResult>();
          await hit(t, 'pointer', 'account-compatibility-cancel');
          p.cancellation!.complete(
            const AccountPortResult.failed(
              AccountFailure(
                code: 'cancel-refused',
                messageKey: 'account.error.writeRejected',
                retryable: true,
              ),
            ),
          );
          p.cancellation = null;
          await t.pumpAndSettle();
          await hit(t, 'pointer', 'account-compatibility-link');
          await t.pumpAndSettle();
          expect(
            t
                .widget<TextFormField>(
                  find.byKey(const Key('account-legacy-password')),
                )
                .controller!
                .text,
            isEmpty,
          );
          p.held = Completer<AccountPortResult>();
          await submit(t, 'keyboard');
          old.complete(
            const AccountPortResult.failed(
              AccountFailure(
                code: 'old-refusal',
                messageKey: 'account.error.writeRejected',
                retryable: true,
              ),
            ),
          );
          await t.pump();
          await t.pump();
          expect(
            m.projection.value.operation,
            AccountOperation.linkingLegacyAccount,
          );
          expect(
            InteractionScope.of(t.element(find.byType(SuiteProgressBar)))
                .reduceMotion,
            isTrue,
          );
          expect(p.commands.whereType<LinkLegacyAccount>(), hasLength(2));
          p.held!.complete(
            await p.delegate.execute(
              p.commands.whereType<LinkLegacyAccount>().last,
            ),
          );
          p.held = null;
          await t.pumpAndSettle();
          expect(
            m.projection.value.notice?.messageKey,
            'account.compatibility.linked',
          );
        } finally {
          await cleanup(t, m, p);
        }
      },
    );
    testWidgets(
      '$suite live theme/reduce keeps credential editor and fields intact',
      (t) async {
        final p = CompatibilityPort(), m = createAccountModule(p);
        try {
          await m.initialize();
          await openLink(t, m, p, suite, 'pointer');
          await t.enterText(
            find.byKey(const Key('account-legacy-name')),
            'legacy-demo',
          );
          final name = t
              .widget<TextFormField>(
                find.byKey(const Key('account-legacy-name')),
              )
              .controller!;
          await t.pumpWidget(
            scopedApp(AccountPage(module: m), suite, reduce: true, light: true),
          );
          await t.pump();
          await t.pump();
          final context = t.element(
            find.byKey(const Key('account-legacy-name')),
          );
          expect(InteractionScope.of(context).reduceMotion, isTrue);
          expect(Theme.of(context).brightness, Brightness.light);
          expect(
            (ModalRoute.of(context) as StarBridgeDialogRoute).animation!.value,
            1,
          );
          expect(
            identical(
              t
                  .widget<TextFormField>(
                    find.byKey(const Key('account-legacy-name')),
                  )
                  .controller,
              name,
            ),
            isTrue,
          );
          expect(name.text, 'legacy-demo');
          await hit(t, 'keyboard', 'account-legacy-dialog-close');
          await t.pumpAndSettle();
          expect(p.commands, isEmpty);
        } finally {
          await cleanup(t, m, p);
        }
      },
    );
    testWidgets(
      '$suite true capability loss retires credentials without command',
      (t) async {
        final p = CompatibilityPort(), m = createAccountModule(p);
        try {
          await m.initialize();
          await openLink(t, m, p, suite, 'pointer');
          await t.enterText(
            find.byKey(const Key('account-legacy-password')),
            'unit-test-only',
          );
          final original = p.delegate.snapshot;
          p.replacement = AccountHostSnapshot(
            generation: original.generation,
            sessionState: original.sessionState,
            route: original.route,
            profile: original.profile,
            profileFreshness: original.profileFreshness,
            identity: original.identity,
            compatibility: const AccountCompatibilityProjection.retired(),
            localeOptions: original.localeOptions,
            timeZoneOptions: original.timeZoneOptions,
            supportsPreferenceWrite: original.supportsPreferenceWrite,
            supportsCacheClear: original.supportsCacheClear,
          );
          await m.refresh();
          await t.pumpAndSettle();
          expect(find.byKey(const Key('account-legacy-name')), findsNothing);
          expect(
            find.byKey(const Key('account-compatibility-link')),
            findsNothing,
          );
          expect(
            find.byKey(const Key('account-compatibility-create')),
            findsNothing,
          );
          expect(p.commands, isEmpty);
        } finally {
          await cleanup(t, m, p);
        }
      },
    );
    testWidgets(
      '$suite repeated link opener owns one prompt and cancellation clears it',
      (t) async {
        final p = CompatibilityPort(), m = createAccountModule(p);
        try {
          await m.initialize();
          await mount(t, m, suite);
          final open = button(t, 'account-compatibility-link').onActivate!;
          open(InteractionSource.pointer);
          open(InteractionSource.pointer);
          await t.pumpAndSettle();
          expect(find.byKey(const Key('account-legacy-name')), findsOneWidget);
          await t.sendKeyEvent(LogicalKeyboardKey.escape);
          await t.pump();
          await t.pump();
          expect(find.byKey(const Key('account-legacy-name')), findsNothing);
          await hit(t, 'pointer', 'account-compatibility-link');
          await t.pumpAndSettle();
          expect(find.byKey(const Key('account-legacy-name')), findsOneWidget);
          await hit(t, 'pointer', 'account-legacy-dialog-cancel');
          await t.pumpAndSettle();
          expect(p.commands, isEmpty);
        } finally {
          await cleanup(t, m, p);
        }
      },
    );
    testWidgets(
      '$suite cancel acknowledgement preserves an already consumed link proof',
      (t) async {
        final p = CompatibilityPort(), m = createAccountModule(p);
        try {
          await m.initialize();
          await openLink(t, m, p, suite, 'pointer');
          p.heldType = LinkLegacyAccount;
          p.held = Completer<AccountPortResult>();
          await submit(t, 'pointer');
          p.cancellation = Completer<AccountPortResult>();
          await hit(t, 'keyboard', 'account-compatibility-cancel');
          final confirmed = await p.delegate.execute(
            p.commands.whereType<LinkLegacyAccount>().single,
          );
          p.cancellation!.complete(
            AccountPortResult.cancelled(confirmed.snapshot!),
          );
          p.cancellation = null;
          await t.pumpAndSettle();
          expect(
            m.projection.value.compatibility.identityState,
            AccountCompatibilityIdentityState.linked,
          );
          expect(
            m.projection.value.notice?.messageKey,
            'account.compatibility.cancelled',
          );
          expect(
            find.byKey(const Key('account-compatibility-cancel')),
            findsNothing,
          );
        } finally {
          await cleanup(t, m, p);
        }
      },
    );
    testWidgets(
      '$suite background refresh retains credential draft and waits before submitting',
      (t) async {
        final p = CompatibilityPort(), m = createAccountModule(p);
        try {
          await m.initialize();
          await openLink(t, m, p, suite, 'pointer');
          await t.enterText(
            find.byKey(const Key('account-legacy-password')),
            'unit-test-only',
          );
          final edit = t
              .widget<TextFormField>(
                find.byKey(const Key('account-legacy-password')),
              )
              .controller!;
          p.pendingRead = Completer<AccountPortResult>();
          unawaited(m.refresh());
          await t.pump();
          await t.pump();
          expect(
            find.byKey(const Key('account-legacy-password')),
            findsOneWidget,
          );
          expect(edit.text, 'unit-test-only');
          expect(button(t, 'account-legacy-submit').onActivate, isNull);
          p.pendingRead!.complete(
            AccountPortResult.completed(p.delegate.snapshot),
          );
          p.pendingRead = null;
          await t.pumpAndSettle();
          expect(
            identical(
              t
                  .widget<TextFormField>(
                    find.byKey(const Key('account-legacy-password')),
                  )
                  .controller,
              edit,
            ),
            isTrue,
          );
          expect(button(t, 'account-legacy-submit').onActivate, isNotNull);
          await hit(t, 'keyboard', 'account-legacy-dialog-close');
          await t.pumpAndSettle();
          expect(p.commands, isEmpty);
        } finally {
          if (p.pendingRead != null && !p.pendingRead!.isCompleted) {
            p.pendingRead!.complete(
              AccountPortResult.completed(p.delegate.snapshot),
            );
          }
          await cleanup(t, m, p);
        }
      },
    );
    for (final opening in ['pointer', 'keyboard', 'reader']) {
      for (final confirming in ['pointer', 'keyboard', 'reader']) {
        for (final outcome in ['success', 'failed', 'cancelled']) {
          testWidgets(
            '$suite $opening to $confirming manual link $outcome retains command and acknowledgement',
            (t) async {
              final p = CompatibilityPort(),
                  m = createAccountModule(p),
                  semantics = t.ensureSemantics();
              try {
                await m.initialize();
                await openLink(t, m, p, suite, opening);
                final route = ModalRoute.of(
                  t.element(find.byKey(const Key('account-legacy-name'))),
                ) as StarBridgeDialogRoute;
                expect(route.instant, opening != 'pointer');
                p.heldType = LinkLegacyAccount;
                p.held = Completer<AccountPortResult>();
                await submit(t, confirming);
                expect(p.commands.whereType<LinkLegacyAccount>(), hasLength(1));
                final command = p.commands
                    .whereType<LinkLegacyAccount>()
                    .single;
                expect(command.credential?.accountName, 'legacy-demo');
                expect(command.credential?.password, 'unit-test-only');
                expect(
                  find.byKey(const Key('account-legacy-password')),
                  findsNothing,
                );
                final wait = find.byType(SuiteProgressBar);
                expect(wait, findsOneWidget);
                expect(
                  InteractionScope.of(t.element(wait)).reduceMotion,
                  confirming != 'pointer',
                );
                expect(
                  button(t, 'account-compatibility-cancel').onActivate,
                  isNotNull,
                );
                p.held!.complete(
                  outcome == 'success'
                      ? await p.delegate.execute(command)
                      : outcome == 'cancelled'
                      ? AccountPortResult.cancelled(p.delegate.snapshot)
                      : const AccountPortResult.failed(
                          AccountFailure(
                            code: 'refused',
                            messageKey: 'account.error.writeRejected',
                            retryable: true,
                          ),
                        ),
                );
                p.held = null;
                await t.pumpAndSettle();
                expect(
                  m.projection.value.compatibility.identityState ==
                      AccountCompatibilityIdentityState.linked,
                  outcome == 'success',
                );
                expect(
                  m.projection.value.notice?.messageKey ==
                      'account.compatibility.linked',
                  outcome == 'success',
                );
                expect(
                  p.commands.whereType<CreateCompatibilityIdentity>(),
                  isEmpty,
                );
                expect(p.commands.whereType<LogoutAccount>(), isEmpty);
              } finally {
                await cleanup(t, m, p);
                semantics.dispose();
              }
            },
          );
        }
      }
      testWidgets(
        '$suite $opening close manual prompt is not a link/cancel/logout command',
        (t) async {
          final p = CompatibilityPort(),
              m = createAccountModule(p),
              semantics = t.ensureSemantics();
          try {
            await m.initialize();
            await openLink(t, m, p, suite, opening);
            await hit(t, opening, 'account-legacy-dialog-close');
            await t.pumpAndSettle();
            expect(find.byKey(const Key('account-legacy-name')), findsNothing);
            expect(p.commands, isEmpty);
          } finally {
            await cleanup(t, m, p);
            semantics.dispose();
          }
        },
      );
      testWidgets('$suite $opening cancel active link waits for server reply', (
        t,
      ) async {
        final p = CompatibilityPort(),
            m = createAccountModule(p),
            semantics = t.ensureSemantics();
        try {
          await m.initialize();
          await openLink(t, m, p, suite, 'pointer');
          p.heldType = LinkLegacyAccount;
          p.held = Completer<AccountPortResult>();
          await submit(t, 'pointer');
          p.cancellation = Completer<AccountPortResult>();
          await hit(t, opening, 'account-compatibility-cancel');
          expect(
            m.projection.value.operation,
            AccountOperation.cancellingCompatibilityOperation,
          );
          expect(button(t, 'account-compatibility-cancel').onActivate, isNull);
          expect(
            p.commands.whereType<CancelCompatibilityOperation>(),
            hasLength(1),
          );
          expect(
            InteractionScope.of(t.element(find.byType(SuiteProgressBar)))
                .reduceMotion,
            opening != 'pointer',
          );
          p.cancellation!.complete(
            AccountPortResult.cancelled(p.delegate.snapshot),
          );
          p.cancellation = null;
          await t.pumpAndSettle();
          expect(
            m.projection.value.notice?.messageKey,
            'account.compatibility.cancelled',
          );
          p.held!.complete(
            await p.delegate.execute(
              p.commands.whereType<LinkLegacyAccount>().single,
            ),
          );
          p.held = null;
          await t.pumpAndSettle();
          expect(
            m.projection.value.compatibility.identityState,
            AccountCompatibilityIdentityState.unlinked,
          );
          expect(p.commands.whereType<LogoutAccount>(), isEmpty);
        } finally {
          await cleanup(t, m, p);
          semantics.dispose();
        }
      });
      testWidgets(
        '$suite $opening retry message preserves refresh/coalescing owner',
        (t) async {
          final p = CompatibilityPort(),
              m = createAccountModule(p),
              semantics = t.ensureSemantics();
          try {
            await m.initialize();
            p.delegate.nextFailure = const AccountFailure(
              code: 'temporary',
              messageKey: 'account.error.writeRejected',
              retryable: true,
            );
            await m.refresh();
            await mount(t, m, suite);
            expect(button(t, 'account-message-action').onActivate, isNotNull);
            final count = p.reads;
            p.pendingRead = Completer<AccountPortResult>();
            await hit(t, opening, 'account-message-action');
            expect(p.reads, count + 1);
            await hit(t, opening, 'account-message-action');
            expect(p.reads, count + 1);
            p.pendingRead!.complete(
              AccountPortResult.completed(p.delegate.snapshot),
            );
            p.pendingRead = null;
            await t.pumpAndSettle();
            expect(p.reads, count + 2);
            expect(p.commands, isEmpty);
            expect(m.projection.value.failure, isNull);
          } finally {
            await cleanup(t, m, p);
            semantics.dispose();
          }
        },
      );
      testWidgets(
        '$suite $opening compatibility refresh reads without auto-link/provisioning',
        (t) async {
          final p = CompatibilityPort(),
              m = createAccountModule(p),
              semantics = t.ensureSemantics();
          try {
            await m.initialize();
            await mount(t, m, suite);
            expect(
              button(t, 'account-compatibility-refresh').onActivate,
              isNotNull,
            );
            final count = p.reads;
            await hit(t, opening, 'account-compatibility-refresh');
            await t.pumpAndSettle();
            expect(p.reads, count + 1);
            expect(p.commands, isEmpty);
            expect(
              find.byKey(const Key('account-compatibility-create')),
              findsNothing,
            );
          } finally {
            await cleanup(t, m, p);
            semantics.dispose();
          }
        },
      );
    }
    testWidgets(
      '$suite invalid input and keyboard IME submit preserve validation and clear password',
      (t) async {
        final p = CompatibilityPort(), m = createAccountModule(p);
        try {
          await m.initialize();
          await openLink(t, m, p, suite, 'pointer');
          await hit(t, 'pointer', 'account-legacy-submit');
          expect(p.commands, isEmpty);
          expect(
            find.byKey(const Key('account-legacy-password')),
            findsOneWidget,
          );
          final controller = t
              .widget<TextFormField>(
                find.byKey(const Key('account-legacy-password')),
              )
              .controller!;
          await t.enterText(
            find.byKey(const Key('account-legacy-name')),
            'legacy-demo',
          );
          await t.enterText(
            find.byKey(const Key('account-legacy-password')),
            'unit-test-only',
          );
          p.heldType = LinkLegacyAccount;
          p.held = Completer<AccountPortResult>();
          await t.testTextInput.receiveAction(TextInputAction.done);
          await t.pump();
          await t.pump();
          expect(controller.text, isEmpty);
          expect(p.commands.whereType<LinkLegacyAccount>(), hasLength(1));
          expect(
            InteractionScope.of(t.element(find.byType(SuiteProgressBar)))
                .reduceMotion,
            isTrue,
          );
        } finally {
          await cleanup(t, m, p);
        }
      },
    );
    testWidgets(
      '$suite replacement owner retires only its credential dialog and stale submit is inert',
      (t) async {
        final p = CompatibilityPort(),
            m = createAccountModule(p),
            q = CompatibilityPort(),
            next = createAccountModule(q);
        try {
          await m.initialize();
          await next.initialize();
          await openLink(t, m, p, suite, 'pointer');
          final submitOld = button(t, 'account-legacy-submit').onActivate!;
          final context = t.element(
            find.byKey(const Key('account-legacy-name')),
          );
          unawaited(
            showStarBridgeDialog(
              context,
              builder: (_) => const AlertDialog(content: Text('unrelated')),
            ),
          );
          await t.pumpAndSettle();
          await mount(t, next, suite);
          expect(find.text('unrelated'), findsOneWidget);
          expect(find.byKey(const Key('account-legacy-name')), findsNothing);
          submitOld(InteractionSource.pointer);
          await t.pumpAndSettle();
          expect(p.commands, isEmpty);
          expect(q.commands, isEmpty);
        } finally {
          await cleanup(t, m, p);
          next.dispose();
          await t.runAsync(q.close);
        }
      },
    );
  }
}
