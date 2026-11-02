import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/features/common/user_avatar_menu.dart';
import 'package:starbridge_flutter/features/party_rooms/party_rooms_module.dart';
import 'package:starbridge_flutter/features/party_rooms/room_directory_card.dart';
import 'package:starbridge_flutter/features/party_rooms/room_display.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../features/friends/social_layout_test.dart' show loadFonts, size;
import '../../features/party_rooms/party_rooms_test.dart'
    show ready, room, wire;
import 'interaction_batch3i_test.dart' show scopedApp;

const _callsign = 'Hint callsign';
const _reference = '0123456789abcdef0123456789abcdef';

PartyRoom _room({
  bool permitted = true,
  bool password = false,
  String admission = 'approval',
  String eligibility = 'everyone',
  String members = 'both',
}) {
  final value = room('hint')
    ..['canPreviewMemberProfiles'] = permitted
    ..['passwordRequired'] = password
    ..['admissionMode'] = admission
    ..['eligibility'] = eligibility;
  final original = Map<String, Object?>.from(
    (value['members'] as List).single as Map,
  );
  value['members'] = [
    if (members != 'locked')
      {...original, 'callsign': _callsign, 'userRef': _reference},
    if (members != 'callsign')
      {
        ...original,
        'callsign': 'Hidden identity',
        'userRef': null,
        'isHost': false,
      },
  ];
  return ready(wire(rooms: [value])).directory!.rooms.single;
}

String _semantics(WidgetTester t) {
  final parts = <String>[];
  void visit(SemanticsNode node) {
    final data = node.getSemanticsData();
    parts.addAll([data.label, data.hint, data.tooltip]);
    node.visitChildren((child) {
      visit(child);
      return true;
    });
  }

  visit(t.binding.renderViews.single.owner!.semanticsOwner!.rootSemanticsNode!);
  return parts.join('\n');
}

List<SuiteTooltipState> _showing(WidgetTester t) => t
    .stateList<SuiteTooltipState>(find.byType(SuiteTooltip))
    .where((state) => state.isShowing)
    .toList();

Future<void> _frames(WidgetTester t, [int count = 3]) async {
  await t.pump();
  for (var i = 0; i < count; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

class _HintProbe {
  _HintProbe(this.suite, this.kind);
  final InteractionSuite suite;
  final String kind;
  bool reduce = false;
  Alignment alignment = Alignment.topLeft;
  late StateSetter update;
  Widget app() => StatefulBuilder(
    builder: (context, setState) {
      update = setState;
      return scopedApp(
        Align(
          alignment: alignment,
          child: SizedBox(
            width: kind == 'tag' ? 90 : 40,
            child: kind == 'tag'
                ? RoomTags(room: _room())
                : RoomMemberPreview(room: _room(members: kind)),
          ),
        ),
        suite,
        reduce: reduce,
      );
    },
  );
  Finder get target => find.byType(SuiteTooltip).first;
}

Finder _bubbleText(String message) => find.text(message).last;

Rect _bubbleRect(WidgetTester t, String message) => t.getRect(
  find
      .ancestor(of: _bubbleText(message), matching: find.byType(Container))
      .first,
);

void main() {
  setUpAll(loadFonts);
  for (final suite in InteractionSuite.values) {
    testWidgets('3ff $suite nested avatar has one bubble and both meanings', (
      t,
    ) async {
      size(t, const Size(500, 500));
      final semantics = t.ensureSemantics();
      final mouse = await t.createGesture(kind: ui.PointerDeviceKind.mouse);
      try {
        await t.pumpWidget(scopedApp(RoomMemberPreview(room: _room()), suite));
        await _frames(t);
        final avatar = find.byType(RoomIdentityAvatar);
        expect(avatar, findsOneWidget);
        final menu = AppStrings.of(t.element(avatar)).text('avatar.menu');
        final spoken = _semantics(t);
        expect(spoken, contains(_callsign));
        expect(spoken, contains(menu));
        await mouse.addPointer(location: const Offset(490, 490));
        await mouse.moveTo(t.getCenter(avatar));
        await t.pump(const Duration(milliseconds: 451));
        await _frames(t);
        expect(
          _showing(t),
          hasLength(1),
          reason: 'Nested hints must not overlap',
        );
        final bubble = _showing(t).single.widget.message;
        expect(bubble, contains(_callsign));
        expect(bubble, contains(menu));
        expect(t.takeException(), isNull);
      } finally {
        await mouse.removePointer();
        await t.pumpWidget(const SizedBox());
        await _frames(t);
        semantics.dispose();
      }
    });

    testWidgets('3ff $suite avatar menu remains an independent action', (
      t,
    ) async {
      size(t, const Size(500, 500));
      final semantics = t.ensureSemantics();
      try {
        await t.pumpWidget(scopedApp(RoomMemberPreview(room: _room()), suite));
        await _frames(t);
        final avatar = find.byType(RoomIdentityAvatar);
        final menu = t.widget<UserAvatarMenu>(
          find.descendant(of: avatar, matching: find.byType(UserAvatarMenu)),
        );
        expect(menu.target!.reference, _reference);
        expect(menu.target!.query, '');
        expect(menu.includeSocialActions, isFalse);
        expect(_semantics(t), isNot(contains('Citizen_CN')));
        expect(_semantics(t), isNot(contains('Hidden identity')));
        await t.tap(avatar);
        await _frames(t, 8);
        final copy = AppStrings.of(t.element(avatar));
        expect(find.text(copy.text('avatar.viewProfile')), findsOneWidget);
        expect(find.text(_callsign), findsOneWidget);
        await t.sendKeyEvent(LogicalKeyboardKey.escape);
        await _frames(t);
        expect(find.text(copy.text('avatar.viewProfile')), findsNothing);
        expect(t.takeException(), isNull);
      } finally {
        await t.pumpWidget(const SizedBox());
        await _frames(t);
        semantics.dispose();
      }
    });

    testWidgets('3ff $suite original member preview gates remain closed', (
      t,
    ) async {
      size(t, const Size(500, 500));
      final semantics = t.ensureSemantics();
      try {
        for (final value in [
          _room(permitted: false),
          _room(password: true),
          _room(admission: 'invite'),
          _room(admission: 'future'),
          _room(eligibility: 'invite'),
          _room(eligibility: 'future'),
        ]) {
          await t.pumpWidget(scopedApp(RoomMemberPreview(room: value), suite));
          await _frames(t);
          expect(
            find.byKey(const Key('room-member-preview-locked')),
            findsOneWidget,
          );
          expect(find.byType(RoomIdentityAvatar), findsNothing);
          expect(find.byType(UserAvatarMenu), findsNothing);
          expect(find.byType(Image), findsNothing);
          expect(_semantics(t), isNot(contains(_callsign)));
          expect(_semantics(t), isNot(contains('Hidden identity')));
          expect(_semantics(t), isNot(contains('Citizen_CN')));
        }
      } finally {
        await t.pumpWidget(const SizedBox());
        await _frames(t);
        semantics.dispose();
      }
    });

    for (final kind in ['callsign', 'locked', 'tag']) {
      testWidgets('3ff $suite $kind delayed edges leave live reduce and Esc', (
        t,
      ) async {
        size(t, const Size(500, 500));
        final probe = _HintProbe(suite, kind);
        final mouse = await t.createGesture(kind: ui.PointerDeviceKind.mouse);
        try {
          await t.pumpWidget(probe.app());
          await _frames(t);
          final message = t.widget<SuiteTooltip>(probe.target).message;
          expect(message, isNotEmpty);
          // SuiteTooltip intentionally skips delay during continuous browsing.
          // Expire that real-clock grace before asserting a cold hover delay.
          await t.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 420)),
          );
          await mouse.addPointer(location: const Offset(250, 250));
          await mouse.moveTo(t.getCenter(probe.target));
          await t.pump(const Duration(milliseconds: 449));
          expect(_showing(t), isEmpty, reason: 'Cold hover must wait');
          await t.pump(const Duration(milliseconds: 2));
          await t.pump(const Duration(milliseconds: 40));
          probe.update(() => probe.reduce = true);
          await t.pump();
          await t.pump();
          expect(_showing(t), hasLength(1));
          final opacity = t.widget<Opacity>(
            find
                .ancestor(
                  of: _bubbleText(message),
                  matching: find.byType(Opacity),
                )
                .first,
          );
          expect(
            opacity.opacity,
            1,
            reason: 'Live reduced motion finishes entry',
          );
          for (final corner in [
            Alignment.topLeft,
            Alignment.topRight,
            Alignment.bottomLeft,
            Alignment.bottomRight,
          ]) {
            await mouse.moveTo(const Offset(250, 250));
            await _frames(t);
            expect(_showing(t), isEmpty, reason: 'Pointer leave closes hint');
            probe.update(() => probe.alignment = corner);
            await _frames(t);
            await mouse.moveTo(t.getCenter(probe.target));
            await t.pump(const Duration(milliseconds: 451));
            await _frames(t);
            expect(_showing(t), hasLength(1));
            final bubble = _bubbleRect(t, message);
            expect(bubble.left, greaterThanOrEqualTo(7.99));
            expect(bubble.top, greaterThanOrEqualTo(7.99));
            expect(bubble.right, lessThanOrEqualTo(492.01));
            expect(bubble.bottom, lessThanOrEqualTo(492.01));
          }
          // Do not focus a fake descendant: this is the natural pointer path
          // for the real passive tag/locked glyph as well as the avatar.
          await t.sendKeyEvent(LogicalKeyboardKey.escape);
          await _frames(t);
          expect(_showing(t), isEmpty, reason: 'Esc dismisses a hovered hint');
          expect(t.takeException(), isNull);
        } finally {
          await mouse.removePointer();
          await t.pumpWidget(const SizedBox());
          await _frames(t);
        }
      });
    }
  }
}
