import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_action_button.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_dialog.dart';
import 'package:starbridge_flutter/features/common/social_read_activity.dart';
import 'package:starbridge_flutter/features/communities/communities_module.dart';
import 'package:starbridge_flutter/features/communities/community_creation_dialog.dart';
import 'package:starbridge_flutter/features/communities/community_creation_port.dart';
import 'package:starbridge_flutter/features/communities/community_logo_crop.dart';
import 'package:starbridge_flutter/features/communities/community_logo_port.dart';
import 'package:starbridge_flutter/features/communities/community_profile_dialog.dart';
import 'package:starbridge_flutter/features/communities/community_profile_port.dart';
import 'package:starbridge_flutter/features/communities/community_roles_dialog.dart';
import 'package:starbridge_flutter/features/communities/community_roles_port.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../_support/visual_output_dir.dart';
import '../../features/communities/community_creation_dialog_test.dart'
    show FormPort;
import '../../features/communities/community_profile_dialog_test.dart'
    show EditorPort;
import '../../features/communities/community_roles_test.dart'
    show RolesFake, rolesPayload;
import '../../features/friends/social_layout_test.dart' show loadFonts, size;
import 'interaction_batch3i_test.dart' show scopedApp;
import 'interaction_batch3fw_workspace_test.dart' show activate;
import 'interaction_batch3fv_directory_test.dart' show frames, changed;

final _review = visualOutputDir(
  'interaction_motion_batch3fx_20261017',
  legacySubdirectory: 'review',
);

class _Profile extends EditorPort {
  Completer<CommunityEditingProfile>? pendingRead;
  Completer<CommunityProfileOutcome>? pendingSave;
  Completer<CommunityLogoSource?>? pendingPick;
  int reads = 0;
  @override
  Future<CommunityEditingProfile> readProfile({
    String? targetRef,
    String? editRef,
  }) {
    reads++;
    return pendingRead?.future ??
        super.readProfile(targetRef: targetRef, editRef: editRef);
  }

  @override
  Future<CommunityProfileOutcome> saveProfile(
    String requestId,
    String editRef,
    Map<String, Object?> values,
  ) {
    if (pendingSave == null) {
      return super.saveProfile(requestId, editRef, values);
    }
    saves.add(values);
    return pendingSave!.future;
  }

  @override
  Future<CommunityLogoSource?> pickLogo() {
    if (pendingPick == null) return super.pickLogo();
    picks++;
    return pendingPick!.future;
  }
}

class _Creation extends FormPort {
  Completer<CommunityCreationOptions>? pendingRead;
  Completer<CommunityCreationOutcome>? pendingSave;
  Completer<CommunityLogoSource?>? pendingPick;
  int reads = 0;
  @override
  Future<CommunityCreationOptions> creationOptions() {
    reads++;
    return pendingRead?.future ?? super.creationOptions();
  }

  @override
  Future<CommunityCreationOutcome> createCommunity(
    String requestId,
    Map<String, Object?> draft,
  ) {
    if (pendingSave == null) return super.createCommunity(requestId, draft);
    writes.add(draft);
    return pendingSave!.future;
  }

  @override
  Future<CommunityLogoSource?> pickLogo() {
    if (pendingPick == null) return super.pickLogo();
    picks++;
    return pendingPick!.future;
  }
}

class _Probe {
  _Probe(this.kind, this.suite, {this.light = false, this.large = false});
  final String kind;
  final profile = _Profile();
  final creation = _Creation();
  final roles = RolesFake();
  final capture = GlobalKey();
  InteractionSuite suite;
  bool reduce = false, light, large;
  late StateSetter update;
  Widget editor() => switch (kind) {
    'profile' => CommunityProfileDialog(port: profile, targetRef: 'a' * 32),
    'roles' => CommunityRolesDialog(port: roles, targetRef: 'a' * 32),
    _ => CommunityCreationDialog(
      port: creation,
      invalidations: creation.invalidations,
    ),
  };
  Widget app() => RepaintBoundary(
    key: capture,
    child: StatefulBuilder(
      builder: (context, set) {
        update = set;
        final base = scopedApp(
          Builder(
            builder: (context) => StarBridgeActionButton(
              controlKey: const Key('open-editor'),
              onActivate: (_) => showStarBridgeDialog<void>(
                context,
                barrierDismissible: false,
                builder: (_) => editor(),
              ),
              child: const Text('Open editor'),
            ),
          ),
          suite,
          light: light,
          reduce: reduce,
        ) as MaterialApp;
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: base.theme,
          themeAnimationDuration: Duration.zero,
          locale: base.locale,
          supportedLocales: base.supportedLocales,
          localizationsDelegates: base.localizationsDelegates,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(large ? 1.5 : 1)),
            child: base.builder!(context, child),
          ),
          home: base.home,
        );
      },
    ),
  );
  Future<void> clean(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    await profile.changes.close();
    await creation.changes.close();
    await roles.events.close();
    expect(t.takeException(), isNull);
  }
}

// ignore: library_private_types_in_public_api
Future<void> open(WidgetTester t, _Probe p, String source) async {
  size(t, const Size(1200, 1100));
  await t.pumpWidget(p.app());
  await frames(t);
  await activate(t, const Key('open-editor'), source);
  await frames(t);
}

Finder marker(String kind, String phase) =>
    find.byKey(ValueKey('$kind-$phase-activity'));
void waitState(WidgetTester t, Finder target, {required bool animated}) {
  expect(target, findsOneWidget);
  final busy = find.descendant(
    of: target,
    matching: find.byType(SuiteBusyFrame),
  );
  expect(busy, findsOneWidget);
  expect(InteractionScope.of(t.element(busy)).reduceMotion, !animated);
}

// ignore: library_private_types_in_public_api
Future<void> fill(WidgetTester t, _Probe p) async {
  if (p.kind == 'creation') {
    for (final (key, text) in [
      ('create-name', 'Motion Fleet'),
      ('create-code', 'MOTION'),
    ]) {
      final target = find.byKey(ValueKey(key));
      await t.ensureVisible(target);
      await t.enterText(target, text);
      await frames(t, 2);
    }
  } else if (p.kind == 'profile') {
    final state = t.state<CommunityProfileDialogState>(
      find.byType(CommunityProfileDialog),
    );
    final field = find.byKey(ValueKey('profile-${state.serial}-description'));
    await t.ensureVisible(field);
    await t.enterText(field, 'Unsaved motion description');
    await frames(t);
  } else {
    await t.tap(find.byKey(const ValueKey('role-custom_navigation')));
    await frames(t);
    // A retained text controller may already display this spelling after the
    // same-lease readback. Model the user's erase/retype, not an identical
    // editing value (which Flutter correctly does not emit as a new change).
    await t.enterText(find.byKey(const ValueKey('role-name')), '');
    await frames(t, 2);
    await t.enterText(find.byKey(const ValueKey('role-name')), '测试领航');
    await frames(t);
  }
}

// ignore: library_private_types_in_public_api
Future<void> save(WidgetTester t, _Probe p, String source) async {
  final key = p.kind == 'creation'
      ? 'community-create-submit'
      : '${p.kind}-save';
  await activate(t, Key(key), source);
  if (p.kind == 'creation') {
    await frames(t, 40);
    await activate(t, const Key('community-create-confirm-save'), source);
  }
}

Future<List<int>> pixels(
  WidgetTester t,
  // ignore: library_private_types_in_public_api
  _Probe p,
  Rect rect, {
  String? png,
}) async {
  final boundary =
      p.capture.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  return (await t.runAsync(() async {
    final image = await boundary.toImage();
    try {
      if (png != null) {
        await Directory(_review).create(recursive: true);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        await File('$_review/$png.png')
            .writeAsBytes(data!.buffer.asUint8List());
      }
      final raw = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!
          .buffer
          .asUint8List();
      return [
        for (var y = rect.top.ceil(); y < rect.bottom.floor(); y++)
          ...raw.sublist(
            (y * image.width + rect.left.ceil()) * 4,
            (y * image.width + rect.right.floor()) * 4,
          ),
      ];
    } finally {
      image.dispose();
    }
  }))!;
}

void main() {
  setUpAll(loadFonts);
  testWidgets('3fx held keyboard creation picker keeps crop instant', (
    t,
  ) async {
    final p = _Probe('creation', InteractionSuite.rail);
    final pending = Completer<CommunityLogoSource?>();
    p.creation.pendingPick = pending;
    try {
      await open(t, p, 'pointer');
      await t.ensureVisible(
        find.byKey(const Key('community-create-pick-logo')),
      );
      await activate(t, const Key('community-create-pick-logo'), 'keyboard');
      await frames(t, 40);
      pending.complete(
        CommunityLogoSource('a' * 32, FormPort.image, 1000, 500),
      );
      await frames(t);
      final route =
          ModalRoute.of(t.element(find.byType(CommunityLogoCrop)))!
              as StarBridgeDialogRoute;
      expect(route.instant, isTrue);
      expect(p.creation.writes, isEmpty);
      await activate(t, const Key('community-crop-cancel'), 'keyboard');
      expect(p.creation.clears, 1);
    } finally {
      await p.clean(t);
    }
  });

  for (final kind in ['profile', 'roles', 'creation']) {
    for (final suite in InteractionSuite.values) {
      if (kind == 'roles') {
        testWidgets(
          '3fx $suite roles uncertain retry uses final confirmation source',
          (t) async {
            final p = _Probe(kind, suite);
            try {
              await open(t, p, 'pointer');
              await fill(t, p);
              p.roles.pendingSave = Completer();
              await save(t, p, 'pointer');
              p.roles.pendingSave!.complete(
                const CommunityProfileOutcome(
                  'unknown',
                  error: 'outcomeUnknown',
                ),
              );
              await frames(t);
              expect(p.roles.writes, 1);
              expect(marker(kind, 'save'), findsNothing);
              await activate(t, const Key('roles-reload'), 'pointer');
              await activate(t, const Key('roles-confirm-accept'), 'keyboard');
              await fill(t, p);
              final owner = t.state<CommunityRolesDialogState>(
                find.byType(CommunityRolesDialog),
              );
              expect(owner.model.requiresRetryConfirmation, isTrue);
              expect(owner.model.dirty, isTrue);
              await save(t, p, 'pointer');
              await frames(t, 40);
              await activate(t, const Key('roles-confirm-cancel'), 'keyboard');
              expect(p.roles.writes, 1);
              p.roles.pendingSave = Completer();
              await save(t, p, 'pointer');
              await frames(t, 40);
              await activate(t, const Key('roles-confirm-accept'), 'keyboard');
              expect(p.roles.writes, 2);
              expect(p.roles.confirmations, [false, true]);
              waitState(t, marker(kind, 'save'), animated: false);
              p.roles.pendingSave!.complete(
                const CommunityProfileOutcome('rejected', error: 'unavailable'),
              );
              await frames(t);
              expect(owner.model.dirty, isTrue);
              expect(p.roles.writes, 2);
            } finally {
              await p.clean(t);
            }
          },
        );
      }
      for (final source in ['pointer', 'keyboard', 'reader']) {
        testWidgets(
          '3fx $kind $suite $source saving keeps draft and readback',
          (t) async {
            final p = _Probe(kind, suite);
            final semantics = t.ensureSemantics();
            try {
              await open(t, p, 'pointer');
              await fill(t, p);
              p.profile.pendingSave = Completer();
              p.roles.pendingSave = Completer();
              p.creation.pendingSave = Completer();
              if (kind == 'creation') {
                await activate(
                  t,
                  const Key('community-create-submit'),
                  source == 'pointer' ? 'keyboard' : 'pointer',
                );
                await activate(
                  t,
                  const Key('community-create-confirm-cancel'),
                  source,
                );
                expect(p.creation.writes, isEmpty);
                await activate(
                  t,
                  const Key('community-create-submit'),
                  source == 'pointer' ? 'keyboard' : 'pointer',
                );
                await frames(t, 40);
                await activate(
                  t,
                  const Key('community-create-confirm-save'),
                  source,
                );
              } else {
                await save(t, p, source);
              }
              waitState(t, marker(kind, 'save'), animated: source == 'pointer');
              final disabled = t
                  .getSemantics(
                    find.byKey(
                      Key(
                        kind == 'creation'
                            ? 'community-create-submit'
                            : '$kind-save',
                      ),
                    ),
                  )
                  .getSemanticsData();
              expect(disabled.hasAction(ui.SemanticsAction.tap), isFalse);
              switch (kind) {
                case 'profile':
                  expect(p.profile.saves, hasLength(1));
                  p.profile.pendingSave!.complete(
                    const CommunityProfileOutcome(
                      'rejected',
                      error: 'unavailable',
                    ),
                  );
                  p.profile.pendingSave = null;
                case 'roles':
                  expect(p.roles.writes, 1);
                  p.roles.pendingSave!.complete(
                    const CommunityProfileOutcome(
                      'rejected',
                      error: 'unavailable',
                    ),
                  );
                  p.roles.pendingSave = null;
                case 'creation':
                  expect(p.creation.writes, hasLength(1));
                  p.creation.pendingSave!.complete(
                    const CommunityCreationOutcome(
                      'rejected',
                      error: 'unavailable',
                    ),
                  );
                  p.creation.pendingSave = null;
              }
              await frames(t);
              expect(marker(kind, 'save'), findsNothing);
              if (kind == 'profile') {
                final owner = t.state<CommunityProfileDialogState>(
                  find.byType(CommunityProfileDialog),
                );
                expect(owner.model.dirty, isTrue);
                expect(
                  owner.model.fields['description'],
                  'Unsaved motion description',
                );
                p.profile.pendingRead = Completer();
              }
              if (kind == 'roles') {
                final owner = t.state<CommunityRolesDialogState>(
                  find.byType(CommunityRolesDialog),
                );
                expect(owner.model.dirty, isTrue);
                expect(owner.model.selected!.name, '测试领航');
                p.roles.pendingRead = Completer();
              }
              final reverse = source == 'pointer' ? 'keyboard' : 'pointer';
              await save(t, p, reverse);
              if (kind == 'creation') {
                expect(p.creation.writes, hasLength(2));
                expect(find.byType(CommunityCreationDialog), findsNothing);
              } else {
                // Acceptance is not completion: original post-save read stays busy.
                waitState(
                  t,
                  marker(kind, 'save'),
                  animated: reverse == 'pointer',
                );
                if (kind == 'profile') {
                  expect(p.profile.saves, hasLength(2));
                  p.profile.pendingRead!.complete(
                    CommunityEditingProfile.parse(p.profile.profile),
                  );
                } else {
                  expect(p.roles.writes, 2);
                  final payload = rolesPayload(revision: 8);
                  for (final row in payload['roles'] as List) {
                    if (row['key'] == 'custom_navigation') {
                      row['displayName'] = '测试领航';
                    }
                  }
                  p.roles.pendingRead!.complete(
                    CommunityEditingRoles.parse(payload),
                  );
                }
                await frames(t);
                expect(marker(kind, 'save'), findsNothing);
                if (kind == 'profile') {
                  expect(
                    t
                        .state<CommunityProfileDialogState>(
                          find.byType(CommunityProfileDialog),
                        )
                        .model
                        .dirty,
                    isFalse,
                  );
                } else {
                  expect(
                    t
                        .state<CommunityRolesDialogState>(
                          find.byType(CommunityRolesDialog),
                        )
                        .model
                        .dirty,
                    isFalse,
                  );
                }
              }
            } finally {
              await p.clean(t);
              semantics.dispose();
            }
          },
        );

        if (kind != 'roles') {
          testWidgets(
            '3fx $kind $suite $source held crop remains instant without upload',
            (t) async {
              final p = _Probe(kind, suite);
              final semantics = t.ensureSemantics();
              final pending = Completer<CommunityLogoSource?>();
              if (kind == 'profile') {
                p.profile.pendingPick = pending;
              } else {
                p.creation.pendingPick = pending;
              }
              try {
                await open(t, p, 'pointer');
                final key = Key(
                  kind == 'profile'
                      ? 'profile-pick-logo'
                      : 'community-create-pick-logo',
                );
                await t.ensureVisible(find.byKey(key));
                await frames(t);
                await activate(t, key, source);
                await frames(t, 40);
                pending.complete(
                  CommunityLogoSource('a' * 32, FormPort.image, 1000, 500),
                );
                await frames(t);
                final route =
                    ModalRoute.of(t.element(find.byType(CommunityLogoCrop)))!
                        as StarBridgeDialogRoute;
                expect(route.instant, source != 'pointer');
                expect(
                  find.byType(SocialReadActivity),
                  findsNothing,
                  reason: 'The covered editor must not keep its wait marker running.',
                );
                await t.pumpAndSettle(
                  const Duration(milliseconds: 16),
                  EnginePhase.sendSemanticsUpdate,
                  const Duration(seconds: 3),
                );
                await activate(t, const Key('community-crop-cancel'), source);
                expect(p.profile.saves, isEmpty);
                expect(p.creation.writes, isEmpty);
                expect(
                  kind == 'profile' ? p.profile.clears : p.creation.clears,
                  1,
                );
              } finally {
                await p.clean(t);
                semantics.dispose();
              }
            },
          );
        }

        testWidgets('3fx $kind $suite $source initial retry and reduce', (
          t,
        ) async {
          final p = _Probe(kind, suite);
          final semantics = t.ensureSemantics();
          p.profile.pendingRead = Completer();
          p.roles.pendingRead = Completer();
          p.creation.pendingRead = Completer();
          try {
            await open(t, p, source);
            waitState(t, marker(kind, 'read'), animated: source == 'pointer');
            p.update(() => p.reduce = true);
            await frames(t, 2);
            waitState(t, marker(kind, 'read'), animated: false);
            p.update(() => p.reduce = false);
            await frames(t, 2);
            waitState(t, marker(kind, 'read'), animated: source == 'pointer');
            switch (kind) {
              case 'profile':
                p.profile.pendingRead!.completeError(
                  const CommunityFailure('unavailable'),
                );
                p.profile.pendingRead = null;
              case 'roles':
                p.roles.pendingRead!.completeError(
                  const CommunityFailure('unavailable'),
                );
                p.roles.pendingRead = null;
              case 'creation':
                p.creation.pendingRead!.completeError(
                  StateError('options failed'),
                );
                p.creation.pendingRead = null;
            }
            await frames(t);
            expect(marker(kind, 'read'), findsNothing);
            final opposite = source == 'pointer' ? 'keyboard' : 'pointer';
            final key = kind == 'creation'
                ? 'community-create-reload'
                : kind == 'profile'
                ? 'profile-read-retry'
                : 'roles-reload';
            if (kind == 'profile') p.profile.pendingRead = Completer();
            if (kind == 'roles') p.roles.pendingRead = Completer();
            if (kind == 'creation') p.creation.pendingRead = Completer();
            await activate(t, Key(key), opposite);
            waitState(t, marker(kind, 'read'), animated: opposite == 'pointer');
            // Close while still reading; late completion must not revive UI.
            await t.pumpWidget(const SizedBox());
            if (kind == 'profile') {
              p.profile.pendingRead!.completeError(StateError('late'));
            }
            if (kind == 'roles') {
              p.roles.pendingRead!.completeError(StateError('late'));
            }
            if (kind == 'creation') {
              p.creation.pendingRead!.completeError(StateError('late'));
            }
            await frames(t);
          } finally {
            await p.clean(t);
            semantics.dispose();
          }
        });
      }

      testWidgets('3fx review $kind $suite save and live reduce', (t) async {
        final p = _Probe(
          kind,
          suite,
          large: true,
          light:
              suite == InteractionSuite.rail || suite == InteractionSuite.glow,
        );
        try {
          await open(t, p, 'pointer');
          await fill(t, p);
          p.profile.pendingSave = Completer();
          p.roles.pendingSave = Completer();
          p.creation.pendingSave = Completer();
          await save(t, p, 'pointer');
          final rect = t.getRect(marker(kind, 'save'));
          final name = '$kind-${suite.name}';
          final first = await pixels(t, p, rect, png: name);
          await frames(t, 12);
          final moving = changed(first, await pixels(t, p, rect));
          expect(moving, greaterThan(0));
          p.update(() => p.reduce = true);
          await frames(t, 2);
          waitState(t, marker(kind, 'save'), animated: false);
          final a = await pixels(t, p, rect);
          await frames(t, 38);
          final still = changed(a, await pixels(t, p, rect));
          expect(still, 0);
          expect(t.getRect(marker(kind, 'save')), rect);
          await t.runAsync(
            () => File('$_review/$name.json').writeAsString(
              jsonEncode({
                'movingPixels': moving,
                'staticPixels': still,
                'rect': [rect.left, rect.top, rect.width, rect.height],
              }),
            ),
          );
          // Retire before the refused response; no state resurrection or resend.
          await t.pumpWidget(const SizedBox());
          if (kind == 'profile') {
            p.profile.pendingSave!.complete(
              const CommunityProfileOutcome('rejected', error: 'unavailable'),
            );
          }
          if (kind == 'roles') {
            p.roles.pendingSave!.complete(
              const CommunityProfileOutcome('rejected', error: 'unavailable'),
            );
          }
          if (kind == 'creation') {
            p.creation.pendingSave!.complete(
              const CommunityCreationOutcome('rejected', error: 'unavailable'),
            );
          }
          await frames(t);
        } finally {
          await p.clean(t);
        }
      });
    }
  }
}
