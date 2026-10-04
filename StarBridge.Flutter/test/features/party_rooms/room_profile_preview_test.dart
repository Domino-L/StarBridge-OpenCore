import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/common/user_avatar_menu.dart';
import 'package:starbridge_flutter/features/common/user_profile_page.dart';
import 'package:starbridge_flutter/features/common/user_interaction.dart';
import 'package:starbridge_flutter/features/personal_profile/bridge_personal_profile_adapter.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_models.dart';
import 'package:starbridge_flutter/features/party_rooms/bridge_party_rooms_adapter.dart';
import 'package:starbridge_flutter/features/party_rooms/room_display.dart';
import 'package:starbridge_flutter/features/party_rooms/room_management_actions.dart';

import 'party_rooms_test.dart' show room, wire, ready, TestRoomsPort, pumpRooms;
import 'room_management_test.dart' show ManagementPort;
import '../friends/social_layout_test.dart' show app, loadFonts;
import '../communities/community_visitor_profile_test.dart'
    show VisitorPort, visitorPayload;

const png =
    'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=';
const reference = '0123456789abcdef0123456789abcdef';

Future<void> captureReview(WidgetTester tester, String name) async {
  if (!const bool.fromEnvironment('ROOM_PROFILE_REVIEW_PNG')) return;
  await tester.runAsync(() async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const Key('room-review-capture')),
    );
    final image = await boundary.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await File('build/room-profile-preview-$name.png')
        .writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  setUpAll(() async {
    if (const bool.fromEnvironment('ROOM_PROFILE_REVIEW_PNG')) {
      await loadFonts();
      await (FontLoader('Source Code Pro')
            ..addFont(rootBundle.load('assets/fonts/SourceCodeVF-Upright.ttf')))
          .load();
    }
  });
  testWidgets(
    'room avatar opens the exact authorized profile when the interaction capability is available',
    (tester) async {
      final port = RoomProfilePort();
      addTearDown(port.changes.close);
      Widget? page;
      final navigation = UserPageNavigation()
        ..open = (context, builder, _) async {
          page = builder(context);
        };
      await tester.pumpWidget(
        app(
          UserInteractionScope(
            navigation: navigation,
            port: port,
            messagePage: null,
            child: const Center(
              child: RoomIdentityAvatar(
                name: '申请者',
                userRef: reference,
                avatarData: png,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(RoomIdentityAvatar));
      await tester.pumpAndSettle();
      final action = find.widgetWithText(MenuItemButton, '查看资料');
      expect(tester.widget<MenuItemButton>(action).onPressed, isNotNull);
      await tester.tap(action);
      await tester.pumpAndSettle();
      expect(page, isA<UserProfilePage>());
      await tester.pumpWidget(app(page!));
      await tester.pumpAndSettle();
      expect(port.requested?.source, 'room');
      expect(port.requested?.reference, reference);
      expect(port.requested?.query, '');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'authorized room avatar strip stays beside facts, wraps narrow and never reveals game ID',
    (tester) async {
      final value = room('a')..['canPreviewMemberProfiles'] = true;
      final members = value['members'] as List;
      (members.first as Map).addAll(<String, Object>{
        'avatarImageData': png,
        'userRef': reference,
      });
      final port = TestRoomsPort()..result = ready(wire(rooms: [value]));
      await pumpRooms(tester, port, const Size(1600, 900));
      final strip = find.byKey(const Key('room-member-preview'));
      expect(strip, findsOneWidget);
      final avatar = find.descendant(
        of: strip,
        matching: find.byType(RoomIdentityAvatar),
      );
      expect(avatar, findsOneWidget);
      expect(
        tester.getTopLeft(strip).dx,
        greaterThan(tester.getTopLeft(find.text('交流语言')).dx),
      );
      final menu = tester.widget<UserAvatarMenu>(
        find.descendant(of: avatar, matching: find.byType(UserAvatarMenu)),
      );
      expect(menu.name, '测试呼号');
      expect(menu.target?.query, '');
      expect(menu.includeSocialActions, isFalse);
      expect(
        find.descendant(of: strip, matching: find.byType(Image)),
        findsOneWidget,
      );
      await captureReview(tester, 'wide');
      await tester.tap(avatar);
      await tester.pumpAndSettle();
      expect(find.text('查看资料'), findsOneWidget);
      await tester.tapAt(const Offset(1200, 750));
      await tester.pumpAndSettle();
      tester.view.physicalSize = const Size(760, 900);
      await tester.pumpAndSettle();
      expect(strip, findsOneWidget);
      expect(tester.takeException(), isNull);
      await captureReview(tester, 'narrow');
      value['passwordRequired'] = true;
      port.result = ready(wire(rooms: [value]));
      port.events.add(null);
      await tester.pumpAndSettle();
      expect(strip, findsNothing);
      expect(
        find.byKey(const Key('room-member-preview-locked')),
        findsOneWidget,
      );
      expect(find.byType(RoomIdentityAvatar), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
  test('unknown, missing and invitation-only preview gates fail closed', () {
    for (final admission in ['direct', 'approval', 'future']) {
      for (final eligibility in [
        'everyone',
        'friends',
        'fleet',
        'invite',
        'future',
      ]) {
        for (final password in [false, true]) {
          final value = room('a')
            ..addAll({
              'canPreviewMemberProfiles': true,
              'admissionMode': admission,
              'eligibility': eligibility,
              'passwordRequired': password,
            });
          expect(
            parseRoomDirectory(wire(rooms: [value]))
                .rooms
                .single
                .canPreviewMemberProfiles,
            !password &&
                admission != 'future' &&
                const {'everyone', 'friends', 'fleet'}.contains(eligibility),
          );
        }
      }
    }
    expect(
      parseRoomDirectory(wire(rooms: [room('a')]))
          .rooms
          .single
          .canPreviewMemberProfiles,
      isFalse,
    );
  });
  testWidgets(
    'sixteen directory members wrap without overflow and private members never expose images or menus',
    (tester) async {
      final value = room('a')
        ..['canPreviewMemberProfiles'] = true
        ..['capacity'] = 16;
      final original = Map<String, Object?>.from(
        (value['members'] as List).single as Map,
      );
      value['members'] = List.generate(
        16,
        (index) => <String, Object?>{
          ...original,
          'callsign': '成员 $index',
          'avatarImageData': png,
          'userRef': index.isEven ? reference : null,
          'isHost': index == 0,
        },
      );
      final port = TestRoomsPort()..result = ready(wire(rooms: [value]));
      await pumpRooms(tester, port, const Size(1280, 950));
      expect(find.byType(RoomIdentityAvatar), findsNWidgets(8));
      expect(
        find.descendant(
          of: find.byKey(const Key('room-member-preview')),
          matching: find.byType(Image),
        ),
        findsNWidgets(8),
      );
      tester.view.physicalSize = const Size(760, 950);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'current host application uses the shared avatar menu and image; loss of role removes it',
    (tester) async {
      final value = room('a')
        ..addAll({
          'viewerIsHost': true,
          'pendingApplications': [
            {
              'applicationId': 'fixture-app',
              'callsign': '申请者',
              'gameId': '',
              'createdAt': '2026-09-05T12:00:00Z',
              'avatarImageData': png,
              'userRef': reference,
            },
          ],
        });
      final port = ManagementPort()
        ..result = ready(wire(current: 'a', rooms: [value]));
      final composition = await pumpRooms(tester, port, const Size(1280, 800));
      expect(find.byType(RoomManagementActions), findsOneWidget);
      await tester.tap(find.widgetWithText(OutlinedButton, '加入申请 · 1'));
      await tester.pumpAndSettle();
      final avatar = find.byKey(const ValueKey('applicant-avatar-fixture-app'));
      expect(avatar, findsOneWidget);
      await captureReview(tester, 'applicant');
      expect(
        find.descendant(of: avatar, matching: find.byType(Image)),
        findsOneWidget,
      );
      final menu = tester.widget<UserAvatarMenu>(
        find.descendant(of: avatar, matching: find.byType(UserAvatarMenu)),
      );
      expect(menu.target?.reference, reference);
      await tester.tap(avatar);
      await tester.pumpAndSettle();
      expect(find.text('查看资料'), findsOneWidget);
      await tester.tapAt(const Offset(1200, 750));
      await tester.pumpAndSettle();
      value['viewerIsHost'] = false;
      port.result = ready(wire(current: 'a', rooms: [value]));
      await composition.partyRooms.refresh();
      await tester.pumpAndSettle();
      expect(avatar, findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
}

class RoomProfilePort extends VisitorPort {
  UserTarget? requested;
  @override
  Future<PersonalProfileSnapshot> profile(UserTarget target) async {
    requested = target;
    return parsePersonalProfileSnapshot(visitorPayload);
  }
}
