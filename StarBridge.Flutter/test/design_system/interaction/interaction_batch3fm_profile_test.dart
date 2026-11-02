import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/composition/menu_profile_page.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_profile_view.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_action_button.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_activation_origin.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_models.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_module.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_page.dart';
import 'package:starbridge_flutter/shared/inline_image_cache.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../app/menu_overlay/menu_chat_media_test.dart' show photo;
import '../../app/menu_overlay/menu_profiles_session_test.dart'
    show fixtureProfile;
import '../../features/friends/social_layout_test.dart' show loadFonts, size;
import 'interaction_batch3b_test.dart' show exposedNodes;
import 'interaction_batch3i_test.dart' show scopedApp;

const toolbarKey = ValueKey('menu-profile-toolbar-refresh');
const logoKey = Key('profile-affiliation-logo-featuredCommunity');

MenuProfileView readyProfile({String about = 'Synthetic profile'}) {
  final encoded = MenuProfileView.encode(fixtureProfile)..['about'] = about;
  ((encoded['affiliations'] as List).single as Map)['image'] = photo;
  return MenuProfileView.parse(encoded);
}

class ProfileProbe {
  ProfileProbe(this.suite);
  InteractionSuite suite;
  MenuProfileView view = readyProfile();
  bool reduce = false, light = false, alternateCallback = false;
  final callbacks = <(String, InteractionSource)>[];
  late StateSetter update;
  Widget app() => StatefulBuilder(
    builder: (_, state) {
      update = state;
      return scopedApp(
        MenuProfileWindowPage(
          view: view,
          onRefresh: () => callbacks.add((
            alternateCallback ? 'replacement' : 'original',
            currentStarBridgeActivationSource,
          )),
        ),
        suite,
        reduce: reduce,
        light: light,
      );
    },
  );
}

Future<void> profileFrames(WidgetTester t) async {
  await t.pump();
  await t.pump();
}

PersonalProfileModule displayModule(WidgetTester t) =>
    t.widget<PersonalProfilePage>(find.byType(PersonalProfilePage)).module;

ImageProvider logoProvider(WidgetTester t) {
  final provider = t.widget<Image>(find.byKey(logoKey)).image;
  return provider is ResizeImage ? provider.imageProvider : provider;
}

void expectVisitor(WidgetTester t) {
  final page = t.widget<PersonalProfilePage>(find.byType(PersonalProfilePage));
  expect(page.isVisitor, isTrue);
  expect(page.module.projection.value.allowEditing, isFalse);
  expect(page.module.projection.value.canEdit, isFalse);
  expect(find.text('编辑个人页面'), findsNothing);
}

void expectToolbarDisabled(WidgetTester t) {
  final control = t.widget(find.byKey(toolbarKey));
  if (control is ButtonStyleButton) {
    expect(control.onPressed, isNull);
  } else {
    expect((control as SuitePressable).onActivate, isNull);
  }
  expect(
    exposedNodes(t).where((n) {
      final d = n.getSemanticsData();
      return d.flagsCollection.isButton &&
          d.label == '刷新个人页面' &&
          d.hasAction(ui.SemanticsAction.tap);
    }),
    isEmpty,
  );
}

Future<void> activateToolbar(WidgetTester t, String input) async {
  final target = find.byKey(toolbarKey);
  expect(target, findsOneWidget);
  if (input == 'reader') {
    final nodes = exposedNodes(t).where((n) {
      final d = n.getSemanticsData();
      return d.flagsCollection.isButton &&
          d.label == '刷新个人页面' &&
          d.hasAction(ui.SemanticsAction.tap);
    }).toList();
    expect(nodes, hasLength(1));
    t.binding.renderViews.single.owner!.semanticsOwner!.performAction(
      nodes.single.id,
      ui.SemanticsAction.tap,
    );
  } else if (input == 'keyboard') {
    final control = t.widget(target);
    final focus = control is ButtonStyleButton
        ? control.focusNode!
        : (control as SuitePressable).focusNode!;
    FocusScope.of(t.element(target)).unfocus();
    await profileFrames(t);
    for (var i = 0; !focus.hasPrimaryFocus && i < 45; i++) {
      await t.sendKeyEvent(LogicalKeyboardKey.tab);
      await profileFrames(t);
    }
    expect(
      focus.hasPrimaryFocus,
      isTrue,
      reason: '$focus\n${FocusManager.instance.toStringDeep()}',
    );
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
  } else {
    final pointer = await t.startGesture(
      t.getCenter(target),
      kind: ui.PointerDeviceKind.touch,
    );
    await pointer.up();
  }
  // Callers check the synchronous callback before scheduling another frame.
}

void main() {
  setUpAll(loadFonts);
  for (final suite in InteractionSuite.values) {
    for (final input in ['touch', 'keyboard', 'reader']) {
      testWidgets(
        '3fm $suite $input toolbar retains display-only read contract',
        (t) async {
          size(t, const Size(1200, 1000));
          final semantics = t.ensureSemantics();
          final p = ProfileProbe(suite);
          try {
            await t.pumpWidget(p.app());
            await profileFrames(t);
            final module = displayModule(t);
            final projection = module.projection.value;
            final source = input == 'touch'
                ? InteractionSource.pointer
                : InteractionSource.keyboard;
            expect(
              p.callbacks,
              isEmpty,
              reason:
                  'Display page does not invent an initial transport request',
            );
            expectVisitor(t);
            final adapter = t.widget<StarBridgeActionButton>(
              find.ancestor(
                of: find.byKey(toolbarKey),
                matching: find.byType(StarBridgeActionButton),
              ),
            );
            expect(adapter.kind, StarBridgeActionKind.quiet);
            for (var i = 0; i < 4; i++) {
              await activateToolbar(t, input);
              expect(p.callbacks, hasLength(i + 1));
              expect(p.callbacks.last, ('original', source));
              expect(
                module.projection.value,
                same(projection),
                reason:
                    'Void refresh callback is not an authoritative read result',
              );
              await profileFrames(t);
            }
            final firstImage = logoProvider(t);
            p.update(() => p.view = const MenuProfileView('loading'));
            await profileFrames(t);
            expect(displayModule(t), same(module));
            expect(
              module.projection.value.availability,
              PersonalProfileAvailability.available,
            );
            expect(
              module.projection.value.operation,
              PersonalProfileOperation.refreshing,
            );
            expect(find.text('Synthetic profile'), findsOneWidget);
            expect(logoProvider(t), same(firstImage));
            expectToolbarDisabled(t);
            await t.tapAt(t.getCenter(find.byKey(toolbarKey)));
            expect(p.callbacks.length, 4);
            p.update(() {
              p.view = readyProfile(about: 'Authoritative response');
              p.reduce = true;
              p.light = true;
              p.alternateCallback = true;
            });
            await profileFrames(t);
            expect(
              module.projection.value.operation,
              PersonalProfileOperation.none,
            );
            expect(find.text('Authoritative response'), findsOneWidget);
            expect(logoProvider(t), same(firstImage));
            await activateToolbar(t, input);
            expect(p.callbacks.length, 5);
            expect(p.callbacks.last, ('replacement', source));
            expectVisitor(t);
            p.update(() => p.view = const MenuProfileView('unavailable'));
            await profileFrames(t);
            expect(find.text('Authoritative response'), findsNothing);
            expect(
              module.projection.value.availability,
              PersonalProfileAvailability.unavailable,
            );
            expect(
              module.projection.value.failureKey,
              'profile.error.unavailable',
            );
            expect(find.byKey(logoKey), findsNothing);
            await activateToolbar(t, input);
            expect(p.callbacks.length, 6);
            expect(
              module.projection.value.availability,
              PersonalProfileAvailability.unavailable,
            );
            p.update(() => p.view = const MenuProfileView('revoked'));
            await profileFrames(t);
            expectToolbarDisabled(t);
            expect(find.text('成员资料已更新。请返回并刷新列表后重试。'), findsOneWidget);
            await t.tapAt(t.getCenter(find.byKey(toolbarKey)));
            expect(p.callbacks.length, 6);
            expectVisitor(t);
            expect(t.takeException(), isNull);
          } finally {
            await t.pumpWidget(const SizedBox());
            semantics.dispose();
          }
        },
      );
    }

    testWidgets(
      '3fm $suite cache boundaries and live suite preserve module owner',
      (t) async {
        size(t, const Size(1200, 1000));
        final p = ProfileProbe(suite);
        await t.pumpWidget(p.app());
        await profileFrames(t);
        final module = displayModule(t);
        var provider = logoProvider(t);
        final cache = t
            .widget<InlineImageCacheScope>(find.byType(InlineImageCacheScope))
            .cache;
        p.update(() {
          p.suite = suite == InteractionSuite.rail
              ? InteractionSuite.glow
              : InteractionSuite.rail;
          p.reduce = true;
          p.light = true;
          p.view = readyProfile();
        });
        await profileFrames(t);
        expect(displayModule(t), same(module));
        expect(
          t
              .widget<InlineImageCacheScope>(find.byType(InlineImageCacheScope))
              .cache,
          same(cache),
        );
        expect(logoProvider(t), same(provider));
        for (final state in ['unavailable', 'notVisible', 'revoked']) {
          p.update(() => p.view = MenuProfileView(state));
          await profileFrames(t);
          expect(find.byKey(logoKey), findsNothing);
          expectVisitor(t);
          expect(module.projection.value.failureKey, switch (state) {
            'notVisible' => 'profile.visitor.notVisible',
            'revoked' => 'profile.visitor.refreshMembers',
            _ => 'profile.error.unavailable',
          });
          p.update(() => p.view = readyProfile());
          await profileFrames(t);
          final next = logoProvider(t);
          expect(
            next,
            isNot(same(provider)),
            reason: '$state purges retained image providers',
          );
          provider = next;
          expect(displayModule(t), same(module));
        }
        expect(p.callbacks, isEmpty);
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
      },
    );

    testWidgets(
      '3fm $suite initial loading and rejected edits do not fabricate reads',
      (t) async {
        size(t, const Size(1200, 1000));
        final semantics = t.ensureSemantics();
        final p = ProfileProbe(suite)..view = const MenuProfileView('loading');
        try {
          await t.pumpWidget(p.app());
          await profileFrames(t);
          final module = displayModule(t);
          expectToolbarDisabled(t);
          expect(
            module.projection.value.availability,
            PersonalProfileAvailability.loading,
          );
          expect(p.callbacks, isEmpty);
          // The existing public interface completes admission immediately. It
          // does not make the display ready or claim that the remote read arrived.
          final result = await module.initialize();
          expect(result.outcome, PersonalProfileActionOutcome.completed);
          expect(p.callbacks.length, 1);
          expect(
            module.projection.value.availability,
            PersonalProfileAvailability.loading,
          );
          final rejected = await module.save(
            const PersonalProfileEdit(
              callSign: 'Rejected write',
              about: 'No edit capability',
              avatarStyle: 0,
              wallpaperId: 'none',
              visibility: PersonalProfileVisibility.friendsOnly,
              moduleLayout: [],
            ),
          );
          expect(rejected.outcome, PersonalProfileActionOutcome.rejected);
          expect(p.callbacks.length, 1);
          expect(
            module.projection.value.availability,
            PersonalProfileAvailability.loading,
          );
          p.update(() => p.view = readyProfile());
          await profileFrames(t);
          expect(find.text('Synthetic profile'), findsOneWidget);
          expectVisitor(t);
          expect(p.callbacks.length, 1);
          expect(t.takeException(), isNull);
        } finally {
          await t.pumpWidget(const SizedBox());
          semantics.dispose();
        }
      },
    );
  }
}
