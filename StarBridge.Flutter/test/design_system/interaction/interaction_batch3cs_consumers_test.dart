import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';
import 'package:starbridge_flutter/app/legal/cig_fankit_notice.dart';
import 'package:starbridge_flutter/features/personal_profile/in_memory_personal_profile_adapter.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_editor.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_models.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_module.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_page.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_port.dart';

import '../../features/friends/social_layout_test.dart' show loadFonts, size;
import 'interaction_batch3i_test.dart' show scopedApp;
import 'interaction_batch3cs_flow_test.dart'
    show activate, buttonNode, clean, closer;

class ProfilePort implements PersonalProfilePort {
  final source = InMemoryPersonalProfileAdapter.forReview(signedIn: true);
  int reads = 0, writes = 0;
  @override
  Stream<void> get invalidations => source.invalidations;
  @override
  Future<PersonalProfileSnapshot> read() {
    reads++;
    return source.read();
  }

  @override
  Future<PersonalProfileActionResult> save(PersonalProfileEdit edit) {
    writes++;
    return source.save(edit);
  }

  @override
  Future<void> close() => source.close();
}

Object? profileSaveActivation(WidgetTester t) {
  final button = t.widget(find.byKey(const Key('profile-save')));
  return button is SuitePressable
      ? button.onActivate
      : (button as FilledButton).onPressed;
}

Future<void> openActual(WidgetTester t, Key key, String source) async {
  await t.ensureVisible(find.byKey(key));
  await t.pumpAndSettle();
  if (source != 'keyboard') {
    await activate(t, key, source);
    return;
  }
  for (var i = 0; i < 128; i++) {
    if (buttonNode(t, key).getSemanticsData().flagsCollection.isFocused ==
        ui.Tristate.isTrue) {
      break;
    }
    await t.sendKeyEvent(LogicalKeyboardKey.tab);
    await t.pump();
  }
  expect(
    buttonNode(t, key).getSemanticsData().flagsCollection.isFocused,
    ui.Tristate.isTrue,
  );
  await t.sendKeyEvent(LogicalKeyboardKey.enter);
  await t.pump();
  await t.pump();
}

void main() {
  setUpAll(loadFonts);
  for (final suite in InteractionSuite.values) {
    for (final source in ['pointer', 'keyboard', 'reader']) {
      testWidgets(
        '$suite actual profile footer notice $source makes no profile writes',
        (t) async {
          size(t, const Size(1280, 1000));
          final semantics = t.ensureSemantics();
          final port = ProfilePort();
          final module = createPersonalProfileModule(port);
          try {
            final initial = await port.read();
            await port.save(
              PersonalProfileEdit(
                callSign: initial.callSign,
                about: initial.about,
                avatarStyle: initial.avatarStyle,
                wallpaperId: 'formation-flight',
                visibility: initial.visibility,
                moduleLayout: initial.moduleLayout,
              ),
            );
            await module.initialize();
            final before = module.projection.value;
            final writes = port.writes, reads = port.reads;
            await t.pumpWidget(
              scopedApp(PersonalProfilePage(module: module), suite),
            );
            await t.pumpAndSettle();
            const key = Key('profile-cig-fankit-notice');
            expect(find.byKey(key), findsOneWidget);
            await openActual(t, key, source);
            await t.pumpAndSettle();
            expect(find.byType(CigFankitNoticeContent), findsOneWidget);
            await activate(t, closer, source);
            await t.pumpAndSettle();
            expect(find.byType(CigFankitNoticeContent), findsNothing);
            expect(identical(module.projection.value, before), isTrue);
            expect(port.writes, writes);
            expect(port.reads, reads);
            expect(t.takeException(), isNull);
          } finally {
            semantics.dispose();
            await clean(t);
            module.dispose();
          }
        },
      );
      testWidgets(
        '$suite actual profile editor notice $source preserves unsaved text',
        (t) async {
          await editor(t, suite, source, pendingSave: false);
        },
      );
    }
    testWidgets(
      '$suite profile notice preserves the original parent save block',
      (t) async {
        await editor(t, suite, 'pointer', pendingSave: true);
      },
    );
  }
}

Future<void> editor(
  WidgetTester t,
  InteractionSuite suite,
  String input, {
  required bool pendingSave,
}) async {
  size(t, const Size(1000, 1000));
  final semantics = t.ensureSemantics();
  final port = ProfilePort();
  final pending = Completer<PersonalProfileActionResult>();
  var writes = 0, cancelled = 0, saved = 0, wallpaperChanges = 0;
  try {
    final projection = PersonalProfileProjection.fromSnapshot(
      await port.read(),
    );
    await t.pumpWidget(
      scopedApp(
        SingleChildScrollView(
          child: PersonalProfileEditorPanel(
            projection: projection,
            moduleLayout: projection.moduleLayout,
            onWallpaperChanged: (_) => wallpaperChanges++,
            onCancel: () => cancelled++,
            onSaved: () => saved++,
            onSave: (_) {
              writes++;
              return pending.future;
            },
          ),
        ),
        suite,
      ),
    );
    await t.pumpAndSettle();
    const about = Key('profile-about-field');
    await t.ensureVisible(find.byKey(about));
    await t.enterText(find.byKey(about), 'Unsubmitted profile draft');
    if (pendingSave) {
      await t.ensureVisible(find.byKey(const Key('profile-save')));
      await t.tap(find.byKey(const Key('profile-save')));
      await t.pump();
      expect(writes, 1);
    }
    if (pendingSave) {
      const notice = Key('profile-editor-cig-fankit-notice');
      await t.ensureVisible(find.byKey(notice));
      await t.pumpAndSettle();
      expect(
        find.ancestor(
          of: find.byKey(notice),
          matching: find.byWidgetPredicate(
            (w) => w is AbsorbPointer && w.absorbing,
          ),
        ),
        findsOneWidget,
      );
      expect(
        buttonNode(
          t,
          notice,
          actionable: false,
        ).getSemanticsData().hasAction(ui.SemanticsAction.tap),
        isFalse,
      );
      expect(find.byType(CigFankitNoticeContent), findsNothing);
      expect(writes, 1);
      pending.complete(
        const PersonalProfileActionResult(PersonalProfileActionOutcome.failed),
      );
      await t.pumpAndSettle();
      expect(profileSaveActivation(t), isNotNull);
    }
    await openActual(t, const Key('profile-editor-cig-fankit-notice'), input);
    await t.pumpAndSettle();
    expect(find.byType(CigFankitNoticeContent), findsOneWidget);
    await activate(t, closer, input);
    await t.pumpAndSettle();
    expect(find.byType(CigFankitNoticeContent), findsNothing);
    expect(
      t.widget<TextField>(find.byKey(about)).controller!.text,
      'Unsubmitted profile draft',
    );
    expect(writes, pendingSave ? 1 : 0);
    expect(cancelled, 0);
    expect(saved, 0);
    expect(wallpaperChanges, 0);
    if (pendingSave) {
      expect(profileSaveActivation(t), isNotNull);
    }
    expect(t.takeException(), isNull);
  } finally {
    if (!pending.isCompleted) {
      pending.complete(
        const PersonalProfileActionResult(PersonalProfileActionOutcome.failed),
      );
    }
    await t.pump();
    semantics.dispose();
    await clean(t);
    await port.close();
  }
}
