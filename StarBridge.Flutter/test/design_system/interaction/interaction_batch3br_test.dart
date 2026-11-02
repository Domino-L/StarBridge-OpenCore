import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';
import 'package:starbridge_flutter/design_system/brand/scm_success_motion.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_action_button.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_icon_action.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_select_form_field.dart';
import 'package:starbridge_flutter/design_system/icons/starbridge_icon.dart';
import 'package:starbridge_flutter/features/account/account_models.dart';
import 'package:starbridge_flutter/features/account/account_module.dart';
import 'package:starbridge_flutter/features/account/account_page.dart';
import 'package:starbridge_flutter/features/account/account_port.dart';

import 'interaction_batch3ad_test.dart' show pick, byControl;
import 'interaction_batch3bg_test.dart' show activate;
import 'interaction_batch3bq_test.dart' show LoginPort, clean, button;
import 'interaction_batch3i_test.dart' show scopedApp;

class PreferencesPort extends LoginPort {
  PreferencesPort() : super.signedIn();
  int reads = 0;
  Completer<AccountPortResult>? pendingRead;
  @override
  Future<AccountPortResult> read() {
    reads++;
    return pendingRead?.future ?? super.read();
  }
}

Future<void> mount(
  WidgetTester t,
  AccountModule module,
  InteractionSuite suite,
) async {
  await t.pumpWidget(scopedApp(AccountPage(module: module), suite));
  await t.pumpAndSettle();
}

Future<void> prepare(
  WidgetTester t,
  AccountModule module,
  InteractionSuite suite,
) async {
  await mount(t, module, suite);
  module.preferencesDraft.setLocale('en-US');
  await t.pump();
  await t.ensureVisible(find.byKey(const Key('account-save-preferences')));
  expect(
    button(t, 'account-save-preferences').kind,
    StarBridgeActionKind.primary,
  );
}

void main() {
  setUpAll(ScmSuccessMotion.verifyArtwork);
  for (final suite in InteractionSuite.values) {
    for (final outcome in ['success', 'cancelled']) {
      testWidgets(
        '$suite late preference $outcome after departure restores the correct draft',
        (t) async {
          final p = PreferencesPort(), m = createAccountModule(p);
          try {
            await m.initialize();
            await prepare(t, m, suite);
            p.heldType = SaveAccountPreferences;
            p.held = Completer<AccountPortResult>();
            await activate(t, 'pointer', const Key('account-save-preferences'));
            final command = p.commands
                .whereType<SaveAccountPreferences>()
                .single;
            await t.pumpWidget(scopedApp(const Text('away'), suite));
            p.held!.complete(
              outcome == 'success'
                  ? await p.delegate.execute(command)
                  : AccountPortResult.cancelled(p.delegate.snapshot),
            );
            p.held = null;
            await t.pumpAndSettle();
            await mount(t, m, suite);
            expect(m.preferencesDraft.locale, 'en-US');
            expect(m.preferencesDraft.hasChanges, outcome != 'success');
            expect(
              m.projection.value.notice?.messageKey,
              outcome == 'success'
                  ? 'account.preferences.saved'
                  : 'account.preferences.cancelled',
            );
            expect(
              p.commands.whereType<SaveAccountPreferences>(),
              hasLength(1),
            );
          } finally {
            await clean(t, m, p);
          }
        },
      );
    }
    testWidgets(
      '$suite old save acknowledgement cannot overwrite the replacement account page',
      (t) async {
        final p = PreferencesPort(),
            m = createAccountModule(p),
            q = PreferencesPort(),
            next = createAccountModule(q);
        try {
          await m.initialize();
          await next.initialize();
          await prepare(t, m, suite);
          p.heldType = SaveAccountPreferences;
          p.held = Completer<AccountPortResult>();
          await activate(t, 'pointer', const Key('account-save-preferences'));
          final command = p.commands.whereType<SaveAccountPreferences>().single;
          await mount(t, next, suite);
          final baseline = next.preferencesDraft.locale;
          p.held!.complete(await p.delegate.execute(command));
          p.held = null;
          await t.pumpAndSettle();
          expect(m.preferencesDraft.locale, 'en-US');
          expect(next.preferencesDraft.locale, baseline);
          expect(next.projection.value.notice, isNull);
          expect(
            t
                .widget<StarBridgeSelectFormField<String>>(
                  find.byKey(const Key('account-locale-field')),
                )
                .initialValue,
            baseline,
          );
          expect(q.commands, isEmpty);
        } finally {
          await clean(t, m, p);
          next.dispose();
          await t.runAsync(q.close);
        }
      },
    );
    testWidgets(
      '$suite replaced-owner menu and late option cannot edit either account',
      (t) async {
        final p = PreferencesPort(),
            m = createAccountModule(p),
            q = PreferencesPort(),
            next = createAccountModule(q);
        try {
          await m.initialize();
          await next.initialize();
          await mount(t, m, suite);
          final baseline = m.preferencesDraft.locale;
          await t.ensureVisible(
            find.byKey(const Key('account-locale-control')),
          );
          await activate(t, 'pointer', const Key('account-locale-control'));
          await t.pumpAndSettle();
          final target = find.byKey(
            const ValueKey<Object>(('account-locale', 'en-US')),
          );
          expect(target, findsOneWidget);
          final control = t.widget(target);
          final VoidCallback late = control is SuitePressable
              ? () => control.onActivate!(InteractionSource.pointer)
              : (control as MenuItemButton).onPressed!;
          await mount(t, next, suite);
          expect(target, findsNothing);
          late();
          await t.pumpAndSettle();
          expect(m.preferencesDraft.locale, baseline);
          expect(next.preferencesDraft.locale, baseline);
          expect(p.commands, isEmpty);
          expect(q.commands, isEmpty);
          expect(t.takeException(), isNull);
        } finally {
          await clean(t, m, p);
          next.dispose();
          await t.runAsync(q.close);
        }
      },
    );
    for (final source in ['pointer', 'keyboard', 'reader']) {
      for (final outcome in ['success', 'cancelled', 'failed']) {
        testWidgets(
          '$suite $source preference $outcome retains authoritative result and retry',
          (t) async {
            final p = PreferencesPort(),
                m = createAccountModule(p),
                semantics = t.ensureSemantics();
            try {
              await m.initialize();
              await prepare(t, m, suite);
              p.heldType = SaveAccountPreferences;
              p.held = Completer<AccountPortResult>();
              final savedAction = button(
                t,
                'account-save-preferences',
              ).onActivate!;
              await activate(t, source, const Key('account-save-preferences'));
              savedAction(InteractionSource.pointer);
              expect(
                p.commands.whereType<SaveAccountPreferences>(),
                hasLength(1),
              );
              final command = p.commands
                  .whereType<SaveAccountPreferences>()
                  .single;
              expect(command.patch.locale, 'en-US');
              expect(command.patch.localeSpecified, isTrue);
              expect(command.patch.timeZoneSpecified, isFalse);
              expect(button(t, 'account-save-preferences').onActivate, isNull);
              expect(
                button(t, 'account-preferences-discard').onActivate,
                isNull,
              );
              expect(m.preferencesDraft.hasChanges, isTrue);
              final wait = find.descendant(
                of: find.byKey(const Key('account-save-preferences')),
                matching: find.byType(SuiteProgressBar),
              );
              expect(wait, findsOneWidget);
              expect(
                InteractionScope.of(t.element(wait)).reduceMotion,
                source != 'pointer',
              );
              final result = outcome == 'success'
                  ? await p.delegate.execute(command)
                  : outcome == 'cancelled'
                  ? AccountPortResult.cancelled(p.delegate.snapshot)
                  : const AccountPortResult.failed(
                      AccountFailure(
                        code: 'refused',
                        messageKey: 'account.preferences.readOnly',
                        retryable: true,
                      ),
                    );
              p.held!.complete(result);
              p.held = null;
              await t.pumpAndSettle();
              expect(m.preferencesDraft.locale, 'en-US');
              expect(m.preferencesDraft.hasChanges, outcome != 'success');
              expect(
                m.projection.value.notice?.messageKey ==
                    'account.preferences.saved',
                outcome == 'success',
              );
              expect(
                button(t, 'account-save-preferences').onActivate,
                isNotNull,
              );
              if (outcome != 'success') {
                await t.ensureVisible(
                  find.byKey(const Key('account-save-preferences')),
                );
                await activate(
                  t,
                  source,
                  const Key('account-save-preferences'),
                );
                await t.pumpAndSettle();
                expect(
                  p.commands.whereType<SaveAccountPreferences>(),
                  hasLength(2),
                );
                expect(m.preferencesDraft.hasChanges, isFalse);
              }
            } finally {
              await clean(t, m, p);
              semantics.dispose();
            }
          },
        );
      }
      testWidgets('$suite $source selecting and discarding does not write', (
        t,
      ) async {
        final p = PreferencesPort(),
            m = createAccountModule(p),
            semantics = t.ensureSemantics();
        try {
          await m.initialize();
          await mount(t, m, suite);
          final baseline = m.preferencesDraft.locale;
          await pick(
            t,
            byControl<String>(const Key('account-locale-control')),
            'en-US',
            source,
          );
          expect(m.preferencesDraft.locale, 'en-US');
          expect(p.commands, isEmpty);
          expect(
            button(t, 'account-preferences-discard').kind,
            StarBridgeActionKind.quiet,
          );
          await t.ensureVisible(
            find.byKey(const Key('account-preferences-discard')),
          );
          await activate(t, source, const Key('account-preferences-discard'));
          await t.pumpAndSettle();
          expect(m.preferencesDraft.locale, baseline);
          expect(
            find.byKey(const Key('account-preferences-unsaved')),
            findsNothing,
          );
          expect(p.commands, isEmpty);
        } finally {
          await clean(t, m, p);
          semantics.dispose();
        }
      });
      testWidgets(
        '$suite $source unchanged save is informational, not a confirmed write',
        (t) async {
          final p = PreferencesPort(),
              m = createAccountModule(p),
              semantics = t.ensureSemantics();
          try {
            await m.initialize();
            await mount(t, m, suite);
            expect(button(t, 'account-save-preferences').onActivate, isNotNull);
            await t.ensureVisible(
              find.byKey(const Key('account-save-preferences')),
            );
            await activate(t, source, const Key('account-save-preferences'));
            await t.pumpAndSettle();
            expect(p.commands, isEmpty);
            expect(
              m.projection.value.notice?.messageKey,
              'account.preferences.noChanges',
            );
            expect(
              m.projection.value.notice?.kind,
              AccountNoticeKind.information,
            );
          } finally {
            await clean(t, m, p);
            semantics.dispose();
          }
        },
      );
      testWidgets(
        '$suite $source profile refresh preserves unsaved draft and disables duplicate read',
        (t) async {
          final p = PreferencesPort(),
              m = createAccountModule(p),
              semantics = t.ensureSemantics();
          try {
            await m.initialize();
            await prepare(t, m, suite);
            final readCount = p.reads;
            p.pendingRead = Completer<AccountPortResult>();
            await t.ensureVisible(find.byKey(const Key('account-refresh')));
            expect(
              find.byWidgetPredicate(
                (w) =>
                    w is StarBridgeIconAction &&
                    w.controlKey == const Key('account-refresh'),
              ),
              findsOneWidget,
            );
            final refreshTarget = find.byWidgetPredicate(
              (w) =>
                  w is StarBridgeIconAction &&
                  w.controlKey == const Key('account-refresh'),
            );
            final previous = t
                .widget<StarBridgeIconAction>(refreshTarget)
                .onActivate!;
            if (source == 'keyboard') {
              Focus.of(
                t.element(
                  find
                      .descendant(
                        of: find.byKey(const Key('account-refresh')),
                        matching: find.byType(StarBridgeIcon),
                      )
                      .first,
                ),
              ).requestFocus();
              await t.pump();
              await t.sendKeyEvent(LogicalKeyboardKey.enter);
              await t.pump();
              await t.pump();
            } else {
              await activate(t, source, const Key('account-refresh'));
            }
            expect(
              t.widget<StarBridgeIconAction>(refreshTarget).onActivate,
              isNull,
            );
            previous(InteractionSource.pointer);
            expect(p.reads, readCount + 1);
            expect(m.preferencesDraft.locale, 'en-US');
            expect(m.projection.value.operation, AccountOperation.refreshing);
            p.pendingRead!.complete(
              AccountPortResult.completed(p.delegate.snapshot),
            );
            p.pendingRead = null;
            await t.pumpAndSettle();
            expect(p.reads, readCount + 1);
            expect(m.preferencesDraft.locale, 'en-US');
            expect(m.preferencesDraft.hasChanges, isTrue);
            expect(p.commands, isEmpty);
          } finally {
            await clean(t, m, p);
            semantics.dispose();
          }
        },
      );
    }
    testWidgets(
      '$suite preference waiting follows live reduce and departure preserves draft',
      (t) async {
        final p = PreferencesPort(), m = createAccountModule(p);
        try {
          await m.initialize();
          await prepare(t, m, suite);
          p.heldType = SaveAccountPreferences;
          p.held = Completer<AccountPortResult>();
          await activate(t, 'pointer', const Key('account-save-preferences'));
          await t.pumpWidget(
            scopedApp(AccountPage(module: m), suite, reduce: true),
          );
          await t.pump();
          final waiting = find.descendant(
            of: find.byKey(const Key('account-save-preferences')),
            matching: find.byType(SuiteProgressBar),
          );
          expect(waiting, findsOneWidget);
          expect(InteractionScope.of(t.element(waiting)).reduceMotion, isTrue);
          await t.pumpWidget(scopedApp(const Text('away'), suite));
          p.held!.complete(
            const AccountPortResult.failed(
              AccountFailure(
                code: 'late refusal',
                messageKey: 'account.preferences.readOnly',
                retryable: true,
              ),
            ),
          );
          p.held = null;
          await t.pumpAndSettle();
          await mount(t, m, suite);
          expect(m.preferencesDraft.locale, 'en-US');
          expect(
            find.byKey(const Key('account-preferences-unsaved')),
            findsOneWidget,
          );
          expect(m.projection.value.failure?.code, 'late refusal');
          expect(p.commands.whereType<SaveAccountPreferences>(), hasLength(1));
        } finally {
          await clean(t, m, p);
        }
      },
    );
    testWidgets(
      '$suite replacement module follows its draft and rejects old action',
      (t) async {
        final p = PreferencesPort(),
            m = createAccountModule(p),
            otherP = PreferencesPort(),
            other = createAccountModule(otherP);
        try {
          await m.initialize();
          await other.initialize();
          await prepare(t, m, suite);
          final oldSave = button(t, 'account-save-preferences').onActivate!;
          await mount(t, other, suite);
          other.preferencesDraft.setLocale('en-US');
          await t.pump();
          expect(
            t
                .widget<StarBridgeSelectFormField<String>>(
                  find.byKey(const Key('account-locale-field')),
                )
                .initialValue,
            'en-US',
          );
          oldSave(InteractionSource.pointer);
          await t.pumpAndSettle();
          expect(p.commands, isEmpty);
          expect(otherP.commands, isEmpty);
        } finally {
          await clean(t, m, p);
          other.dispose();
          await t.runAsync(otherP.close);
        }
      },
    );
  }
}
