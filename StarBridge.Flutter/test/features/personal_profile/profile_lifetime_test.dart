import 'dart:async';

import 'package:starbridge_flutter/features/account/account_models.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_read_status.dart';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/onboarding/connection_mode_port.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_editor.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_models.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_module.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_page.dart';
import 'package:starbridge_flutter/features/personal_profile/profile_read_scope.dart';

import 'package:starbridge_flutter/features/personal_profile/personal_profile_draft.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_playstyle_editor.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_schedule_editor.dart';

import 'package:starbridge_flutter/features/personal_profile/personal_profile_visibility.dart';

import 'profile_handoff_failure_test.dart' show ProfileLifetimeFixture;

Future<void> editDraft(WidgetTester tester) async {
  final edit = find.byKey(const Key('profile-edit'));
  await tester.ensureVisible(edit);
  await tester.pumpAndSettle();
  await tester.tap(edit);
  await tester.pumpAndSettle();
  final about = find.byKey(const Key('profile-about-field'));
  await tester.ensureVisible(about);
  await tester.pumpAndSettle();
  await tester.enterText(about, 'Private unsaved navigation draft');
}

String? draftText(WidgetTester tester) {
  final about = find.byKey(const Key('profile-about-field'));
  return about.evaluate().isEmpty
      ? null
      : tester.widget<TextField>(about).controller!.text;
}

void main() {
  testWidgets(
    'settled old save cannot dispatch its follow-up read under a retired mode',
    (tester) async {
      final f = ProfileLifetimeFixture();
      try {
        await f.mountFeature(tester, authenticated: true);
        await editDraft(tester);
        final page = tester.widget<PersonalProfilePage>(
          find.byType(PersonalProfilePage),
        );
        final edit = tester
            .state<PersonalProfileEditorPanelState>(
              find.byType(PersonalProfileEditorPanel),
            )
            .captureDraft()
            .edit;
        f.port.saveGate = Completer<PersonalProfileActionResult>();
        final saving = page.access!.save(edit);
        await tester.pumpAndSettle();
        expect(f.port.saves, 1);
        f.mode.snapshot = const ConnectionModeSnapshot(
          scope: 99,
          revision: 5,
          state: ConnectionModeState.online,
        );
        f.mode.notifyListeners();
        await tester.pumpAndSettle();
        f.port.saveGate!.complete(
          const PersonalProfileActionResult(
            PersonalProfileActionOutcome.completed,
          ),
        );
        await saving;
        await tester.pumpAndSettle();
        expect(f.port.reads, 1);
        expect(f.port.saves, 1);
        expect(find.byKey(const Key('profile-identity-header')), findsNothing);
        f.port.pending = Completer<PersonalProfileSnapshot>();
        f.mode.snapshot = const ConnectionModeSnapshot(
          scope: 8,
          revision: 4,
          state: ConnectionModeState.online,
        );
        f.mode.notifyListeners();
        await tester.pumpAndSettle();
        expect(f.port.reads, 2);
        f.port.pending!.complete(await f.port.fresh());
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('profile-identity-header')),
          findsOneWidget,
        );
        expect(draftText(tester), isNull);
        expect(f.port.saves, 1);
      } finally {
        await f.close(tester);
      }
    },
  );
  testWidgets(
    'a second mode failure retires the in-flight revalidation again',
    (tester) async {
      final f = ProfileLifetimeFixture();
      try {
        await f.mountFeature(tester, authenticated: true);
        f.mode.failed = true;
        f.mode.notifyListeners();
        await tester.pumpAndSettle();
        final old = f.port.pending = Completer<PersonalProfileSnapshot>();
        f.mode.failed = false;
        f.mode.notifyListeners();
        await tester.pumpAndSettle();
        expect(f.port.reads, 2);
        f.mode.failed = true;
        f.mode.notifyListeners();
        await tester.pumpAndSettle();
        f.mode.failed = false;
        f.mode.notifyListeners();
        await tester.pumpAndSettle();
        f.port.pending = Completer<PersonalProfileSnapshot>();
        old.complete(await f.port.fresh());
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('profile-identity-header')),
          findsNothing,
          reason:
              'The second failed observation retired the first recovery read.',
        );
        expect(f.port.reads, 3);
        f.port.pending!.complete(await f.port.fresh());
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('profile-identity-header')),
          findsOneWidget,
        );
        expect(f.port.reads, 3);
      } finally {
        if (!f.port.pending!.isCompleted) {
          f.port.pending!.complete(await f.port.fresh());
        }
        await f.close(tester);
      }
    },
  );
  testWidgets(
    'first ordinary profile accepts the actual initial receipt without an extra read',
    (tester) async {
      final f = ProfileLifetimeFixture();
      try {
        await f.mountFeature(tester, retained: false);
        expect(f.port.reads, 1);
        expect(f.cache.reads, 0);
        f.account.value = f.account.value.copyWith(
          sessionState: AccountSessionState.signedIn,
          operation: AccountOperation.none,
        );
        await tester.pumpAndSettle();
        f.port.pending!.complete(await f.port.fresh());
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('profile-identity-header')),
          findsOneWidget,
        );
        expect(
          f.port.reads,
          1,
          reason: 'No previous accepted display was retired.',
        );
      } finally {
        await f.close(tester);
      }
    },
  );
  testWidgets(
    'empty signed out status is not replaced by an unavailable guard',
    (tester) async {
      final f = ProfileLifetimeFixture();
      try {
        await f.mountFeature(tester, authenticated: true);
        f.port.pending = Completer<PersonalProfileSnapshot>();
        final reading = f.online.refresh();
        f.account.value = f.account.value.copyWith(
          sessionState: AccountSessionState.signedOut,
        );
        f.port.pending!.complete(const PersonalProfileSnapshot.signedOut());
        await reading;
        await tester.pumpAndSettle();
        expect(find.byType(PersonalProfileSignedOutView), findsOneWidget);
        expect(find.byKey(const Key('profile-identity-header')), findsNothing);
        expect(f.port.saves, 0);
      } finally {
        await f.close(tester);
      }
    },
  );
  testWidgets(
    'hard mode retirement does not drain an old editor queued refresh under an unconfirmed owner',
    (tester) async {
      final f = ProfileLifetimeFixture();
      try {
        await f.mountFeature(tester, authenticated: true);
        await editDraft(tester);
        await f.online.refresh();
        expect(f.port.reads, 1);
        f.port.pending = Completer<PersonalProfileSnapshot>();
        f.mode.snapshot = const ConnectionModeSnapshot(
          scope: 99,
          revision: 5,
          state: ConnectionModeState.online,
        );
        f.mode.notifyListeners();
        await tester.pumpAndSettle();
        expect(
          f.port.reads,
          1,
          reason: 'Retiring an editor is not admission for its deferred read.',
        );
      } finally {
        if (!f.port.pending!.isCompleted) {
          f.port.pending!.complete(await f.port.fresh());
        }
        await f.close(tester);
      }
    },
  );
  testWidgets(
    'visibility read cannot cross a failed mode observation even when the same binding returns',
    (tester) async {
      final f = ProfileLifetimeFixture();
      try {
        await f.mountFeature(tester, authenticated: true);
        final access = tester
            .widget<PersonalProfilePage>(find.byType(PersonalProfilePage))
            .access!;
        f.port.visibilityGate = Completer<ProfileVisibilityState>();
        final reading = access.visibility.readVisibility();
        final expected = expectLater(reading, throwsStateError);
        f.mode.failed = true;
        f.mode.notifyListeners();
        await tester.pumpAndSettle();
        f.mode.failed = false;
        f.mode.notifyListeners();
        await tester.pumpAndSettle();
        f.port.visibilityGate!.complete(
          const ProfileVisibilityState(1, PersonalProfileVisibility.onlyMe),
        );
        await expected;
      } finally {
        await f.close(tester);
      }
    },
  );
  for (final invalidSchedule in [false, true]) {
    testWidgets(
      'restored draft retains all fields and validates changed ${invalidSchedule ? 'schedule' : 'roles'}',
      (tester) async {
        final f = ProfileLifetimeFixture();
        try {
          f.port.local = true;
          await f.mountFeature(tester, authenticated: true);
          f.navigation(() => f.visible = false);
          await tester.pumpAndSettle();
          final edit = PersonalProfileEdit(
            callSign: 'Draft Pilot',
            about: 'All draft fields',
            avatarStyle: 2,
            wallpaperId: 'none',
            visibility: PersonalProfileVisibility.friendsOnly,
            moduleLayout: f.online.projection.value.moduleLayout,
            playStyle: PersonalProfilePlayStyle(
              roles: invalidSchedule ? [] : ['synthetic-unknown-role'],
              interests: ['mining'],
            ),
            schedule: PersonalProfileSchedule(
              timeZoneId: invalidSchedule ? '' : 'UTC',
              rhythm: PersonalProfileActivityRhythm.regular,
              windows: const [
                PersonalProfileAvailabilityWindow(
                  days: [1],
                  startTime: '19:00',
                  endTime: '20:00',
                ),
              ],
            ),
          );
          expect(
            (f.online as PersonalProfileEditingSession).beginEditing(),
            isTrue,
          );
          expect(
            (f.online as PersonalProfileDraftSession).keepEditorDraft(
              PersonalProfileEditorDraft(edit),
            ),
            isTrue,
          );
          f.navigation(() => f.visible = true);
          await tester.pumpAndSettle();
          final restored = tester
              .state<PersonalProfileEditorPanelState>(
                find.byType(PersonalProfileEditorPanel),
              )
              .captureDraft()
              .edit;
          expect(restored.callSign, edit.callSign);
          expect(restored.about, edit.about);
          expect(restored.avatarStyle, edit.avatarStyle);
          expect(restored.wallpaperId, edit.wallpaperId);
          expect(restored.visibility, edit.visibility);
          expect(restored.moduleLayout, edit.moduleLayout);
          expect(restored.playStyle!.toJson(), edit.playStyle!.toJson());
          expect(
            restored.playStyle!.support,
            isNull,
            reason: 'Unchanged groups must retain their omitted-patch meaning.',
          );
          expect(restored.schedule!.toJson(), edit.schedule!.toJson());
          expect(
            tester
                .widget<PersonalProfilePlayStyleEditor>(
                  find.byType(PersonalProfilePlayStyleEditor),
                )
                .initial!
                .toJson(),
            edit.playStyle!.toJson(),
          );
          expect(
            tester
                .widget<PersonalProfileScheduleEditor>(
                  find.byType(PersonalProfileScheduleEditor),
                )
                .initiallyChanged,
            isTrue,
          );
          expect(
            tester.state<FormState>(find.byType(Form)).validate(),
            isFalse,
            reason: 'Restored unsaved choices are not grandfathered as the server baseline.',
          );
          expect(f.port.saves, 0);
          expect(f.port.reads, 1);
        } finally {
          await f.close(tester);
        }
      },
    );
  }
  testWidgets(
    'ordinary visitor preview survives leaving and returning without another read',
    (tester) async {
      final f = ProfileLifetimeFixture();
      try {
        await f.mountFeature(tester, authenticated: true);
        final preview = find.byKey(const Key('profile-preview'));
        await tester.ensureVisible(preview);
        await tester.pumpAndSettle();
        await tester.tap(preview);
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('profile-preview-exit')), findsOneWidget);
        await f.leaveAndReturn(tester);
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('profile-preview-exit')), findsOneWidget);
        expect(f.port.reads, 1);
        expect(f.port.saves, 0);
      } finally {
        await f.close(tester);
      }
    },
  );
  testWidgets(
    'account generation change while away retires draft and old receipt before fresh read',
    (tester) async {
      final f = ProfileLifetimeFixture();
      try {
        await f.mountFeature(tester, authenticated: true);
        await editDraft(tester);
        f.navigation(() => f.visible = false);
        await tester.pumpAndSettle();
        f.account.value = f.account.value.copyWith(generation: 9);
        f.port.activeReadGeneration = 9;
        f.port.nextScope = ProfileReadScope(9, f.port.nextScope.route);
        f.port.pending = Completer<PersonalProfileSnapshot>();
        f.mode.snapshot = const ConnectionModeSnapshot(
          scope: 9,
          revision: 4,
          state: ConnectionModeState.online,
        );
        f.mode.notifyListeners();
        await tester.pumpAndSettle();
        f.navigation(() => f.visible = true);
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('profile-identity-header')), findsNothing);
        expect(draftText(tester), isNull);
        expect(f.port.reads, 2);
        f.port.pending!.complete(await f.port.fresh());
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('profile-identity-header')),
          findsOneWidget,
        );
        expect(draftText(tester), isNull);
        expect(f.port.saves, 0);
      } finally {
        await f.close(tester);
      }
    },
  );
  testWidgets(
    'failed mode quarantines draft; exact confirmed owner resumes original lease without a read',
    (tester) async {
      final f = ProfileLifetimeFixture();
      try {
        await f.mountFeature(tester, authenticated: true);
        await editDraft(tester);
        final access = tester
            .widget<PersonalProfilePage>(find.byType(PersonalProfilePage))
            .access!;
        final edit = tester
            .state<PersonalProfileEditorPanelState>(
              find.byType(PersonalProfileEditorPanel),
            )
            .captureDraft()
            .edit;
        f.mode.failed = true;
        f.mode.notifyListeners();
        await tester.pumpAndSettle();
        expect(find.byType(PersonalProfileEditorPanel), findsNothing);
        expect(find.byKey(const Key('profile-identity-header')), findsNothing);
        expect(
          (await access.save(edit)).outcome,
          PersonalProfileActionOutcome.rejected,
        );
        expect(f.port.saves, 0);
        expect(f.port.reads, 1);
        await f.leaveAndReturn(tester);
        await tester.pumpAndSettle();
        expect(draftText(tester), isNull);
        f.mode.failed = false;
        f.mode.notifyListeners();
        await tester.pumpAndSettle();
        expect(draftText(tester), 'Private unsaved navigation draft');
        expect(f.port.reads, 1);
        expect(f.port.saves, 0);
      } finally {
        await f.close(tester);
      }
    },
  );
  testWidgets(
    'ordinary mode recovery waits for new complete receipt and deduplicates navigation reads',
    (tester) async {
      final f = ProfileLifetimeFixture();
      try {
        await f.mountFeature(tester, authenticated: true);
        f.mode.failed = true;
        f.mode.notifyListeners();
        await tester.pumpAndSettle();
        f.port.pending = Completer<PersonalProfileSnapshot>();
        f.mode.failed = false;
        f.mode.notifyListeners();
        await tester.pumpAndSettle();
        expect(f.port.reads, 2);
        expect(find.byKey(const Key('profile-identity-header')), findsNothing);
        await f.leaveAndReturn(tester);
        await tester.pumpAndSettle();
        expect(f.port.reads, 2);
        expect(find.byKey(const Key('profile-identity-header')), findsNothing);
        f.port.pending!.complete(await f.port.fresh());
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<PersonalProfilePage>(find.byType(PersonalProfilePage))
              .module,
          same(f.online),
        );
        expect(
          find.byKey(const Key('profile-identity-header')),
          findsOneWidget,
        );
        expect(f.port.reads, 2);
      } finally {
        await f.close(tester);
      }
    },
  );
  testWidgets('hard mode change retires parked draft and late editor save', (
    tester,
  ) async {
    final f = ProfileLifetimeFixture();
    try {
      await f.mountFeature(tester, authenticated: true);
      await editDraft(tester);
      final page = tester.widget<PersonalProfilePage>(
        find.byType(PersonalProfilePage),
      );
      final edit = tester
          .state<PersonalProfileEditorPanelState>(
            find.byType(PersonalProfileEditorPanel),
          )
          .captureDraft()
          .edit;
      await f.leaveAndReturn(tester);
      await tester.pumpAndSettle();
      f.mode.snapshot = const ConnectionModeSnapshot(
        scope: 99,
        revision: 5,
        state: ConnectionModeState.online,
      );
      f.mode.notifyListeners();
      await tester.pumpAndSettle();
      expect(
        (await page.access!.save(edit)).outcome,
        PersonalProfileActionOutcome.rejected,
      );
      expect(
        (f.online as PersonalProfileEditingSession).beginEditing(),
        isTrue,
        reason: 'The feature retired its old lease rather than parking it for another mode.',
      );
      (f.online as PersonalProfileEditingSession).endEditing();
      f.port.pending = Completer<PersonalProfileSnapshot>();
      f.mode.snapshot = const ConnectionModeSnapshot(
        scope: 8,
        revision: 4,
        state: ConnectionModeState.online,
      );
      f.mode.notifyListeners();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('profile-identity-header')), findsNothing);
      f.port.pending!.complete(await f.port.fresh());
      await tester.pumpAndSettle();
      expect(draftText(tester), isNull);
      expect(f.port.saves, 0);
    } finally {
      await f.close(tester);
    }
  });
  testWidgets('hard module invalidation while away destroys parked draft', (
    tester,
  ) async {
    final f = ProfileLifetimeFixture();
    try {
      await f.mountFeature(tester, authenticated: true);
      await editDraft(tester);
      f.navigation(() => f.visible = false);
      await tester.pumpAndSettle();
      f.port.pending = Completer<PersonalProfileSnapshot>();
      f.port.hard.add(null);
      f.port.pending!.complete(await f.port.fresh());
      await tester.pumpAndSettle();
      f.navigation(() => f.visible = true);
      await tester.pumpAndSettle();
      expect(draftText(tester), isNull);
      expect(find.byKey(const Key('profile-identity-header')), findsOneWidget);
      expect(f.port.reads, 2);
      expect(f.port.saves, 0);
    } finally {
      await f.close(tester);
    }
  });
  for (final uncertain in [false, true]) {
    testWidgets(
      'save settling while away preserves correct draft outcome: uncertain=$uncertain',
      (tester) async {
        final f = ProfileLifetimeFixture();
        try {
          await f.mountFeature(tester, authenticated: true);
          await editDraft(tester);
          f.port.saveGate = Completer<PersonalProfileActionResult>();
          FocusManager.instance.primaryFocus?.unfocus();
          await tester.pumpAndSettle();
          final save = find.byKey(const Key('profile-save'));
          await tester.ensureVisible(save);
          await tester.pumpAndSettle();
          expect(
            const Rect.fromLTWH(
              0,
              0,
              1280,
              650,
            ).contains(tester.getCenter(save)),
            isTrue,
          );
          await tester.tap(save);
          await tester.pump();
          expect(f.port.saves, 1);
          f.navigation(() => f.visible = false);
          await tester.pumpAndSettle();
          f.port.saveGate!.complete(
            PersonalProfileActionResult(
              uncertain
                  ? PersonalProfileActionOutcome.failed
                  : PersonalProfileActionOutcome.completed,
              requiresReload: uncertain,
            ),
          );
          await tester.pumpAndSettle();
          f.navigation(() => f.visible = true);
          await tester.pumpAndSettle();
          expect(f.port.saves, 1);
          if (uncertain) {
            expect(draftText(tester), 'Private unsaved navigation draft');
            expect(tester.widget<FilledButton>(save).onPressed, isNull);
            expect(f.port.reads, 1);
            final page = tester.widget<PersonalProfilePage>(
              find.byType(PersonalProfilePage),
            );
            expect(
              (await page.access!.save(f.port.savedEdit!)).outcome,
              PersonalProfileActionOutcome.rejected,
            );
            expect(f.port.saves, 1);
          } else {
            expect(draftText(tester), isNull);
            expect(
              find.byKey(const Key('profile-identity-header')),
              findsOneWidget,
            );
            expect(f.port.reads, 2);
          }
        } finally {
          await f.close(tester);
        }
      },
    );
  }
}
