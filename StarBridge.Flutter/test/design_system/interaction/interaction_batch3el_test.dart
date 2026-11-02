import 'dart:ui' show SemanticsAction;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import 'package:starbridge_flutter/features/common/organization_holo_choice.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_dialog.dart';
import 'package:starbridge_flutter/features/common/organization_member_board.dart';
import 'package:starbridge_flutter/features/communities/community_ships_panel.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_models.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_page.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_members_models.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_workspace_navigation.dart';

import 'interaction_batch3h_test.dart' as fixture;
import '../../features/friends/social_layout_test.dart' show loadFonts;

Future<void> _twoFrames(WidgetTester t) async {
  await t.pump();
  await t.pump();
}

FocusNode _buttonOwner(WidgetTester t, String id) {
  final target = find.byKey(Key(id));
  expect(target, findsOneWidget);
  final widget = t.widget(target);
  if (widget is SuitePressable) {
    expect(widget.onActivate, isNotNull);
    return widget.focusNode!;
  }
  expect(widget, isA<ButtonStyleButton>());
  final button = widget as ButtonStyleButton;
  expect(button.onPressed, isNotNull);
  return button.focusNode!;
}

Future<void> _tabTo(
  WidgetTester t,
  FocusNode owner,
  List<FocusNode?> observed, {
  bool activate = true,
}) async {
  expect(owner.canRequestFocus, isTrue);
  var tabs = 0;
  do {
    await t.sendKeyEvent(LogicalKeyboardKey.tab);
    await _twoFrames(t);
    observed.add(FocusManager.instance.primaryFocus);
    tabs++;
  } while (!owner.hasPrimaryFocus && tabs < 64);
  expect(tabs, inInclusiveRange(1, 64));
  expect(FocusManager.instance.primaryFocus, same(owner));
  if (activate) {
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await _twoFrames(t);
  }
}

Future<void> _tap(WidgetTester t, Finder target) async {
  expect(target, findsOneWidget);
  await t.ensureVisible(target);
  await t.pumpAndSettle();
  // Keep the default hit warning, promoted to fatal by the pointer test.
  await t.tap(target);
  await _twoFrames(t);
}

List<FocusNode> _deniedTabs(WidgetTester t) {
  final denied = <FocusNode>[];
  for (final id in ['channel', 'broadcasts']) {
    final target = fixture.tab(id);
    expect(target, findsOneWidget);
    final control = t.widget<OrganizationHoloChoice>(
      find.ancestor(of: target, matching: find.byType(OrganizationHoloChoice)),
    );
    expect(control.onActivate, isNull);
    expect(control.selected, isFalse);
    denied.add(control.focusNode!);
    expect(
      t.getSemantics(target).getSemanticsData().hasAction(SemanticsAction.tap),
      isFalse,
    );
  }
  return denied;
}

void main() {
  setUpAll(loadFonts);
  for (final suite in InteractionSuite.values) {
    for (final source in ['keyboard', 'pointer']) {
      testWidgets(
        '$suite real fleet $source search ships details return retains owners and skips unsupported communication',
        (t) async {
          final originalHitPolicy =
              WidgetController.hitTestWarningShouldBeFatal;
          if (source == 'pointer') {
            WidgetController.hitTestWarningShouldBeFatal = true;
          }
          final semantics = t.ensureSemantics();
          final observed = <FocusNode?>[];
          try {
            // The existing 1280x900 fixture now uses the current shared-ships
            // owner with a verified workspace context. Chat and announcements
            // remain unavailable; membership cannot manufacture capabilities.
            final f = await fixture.fleet(t, suite);
            // Two screens: the top screen's rail opens the member list,
            // activated from the same source as the rest of the test.
            final rail = fixture.tab('members');
            if (source == 'keyboard') {
              Focus.of(
                t.element(
                  find.descendant(of: rail, matching: find.byType(Text)).first,
                ),
              ).requestFocus();
              await t.pump();
              await t.sendKeyEvent(LogicalKeyboardKey.enter);
            } else {
              await t.tap(rail);
            }
            await t.pumpAndSettle();
            final module = f.module;
            final members = module.members;
            final ships = module.ships;
            final communication = module.communication;
            final contextRevision = module.contextRevision;
            final identity = module.projection.value.fleet;
            final page = find.byType(OfficialFleetPage);
            expect(page, findsOneWidget);
            expect(t.widget<OfficialFleetPage>(page).module, same(module));
            expect(
              module.projection.value.availability,
              OfficialFleetAvailability.available,
            );
            expect(identity, isNotNull);
            // sourceRef is data authority, distinct from pointer/keyboard
            // activation provenance exercised by the real controls below.
            expect(identity!.sourceRef, 'officialFleet:7');
            expect(
              members.projection.value.availability,
              OfficialFleetMemberDirectoryAvailability.available,
            );
            expect(members.projection.value.members, hasLength(5));
            expect(
              members.projection.value.query!.sourceRef,
              'officialFleet:7',
            );
            final navigation = find.byType(OfficialFleetWorkspaceNavigation);
            expect(
              t.widget<OfficialFleetWorkspaceNavigation>(navigation).selected,
              OfficialFleetWorkspaceSection.members,
            );
            expect(
              t
                  .widget<OfficialFleetWorkspaceNavigation>(navigation)
                  .availableSections,
              {
                OfficialFleetWorkspaceSection.members,
                OfficialFleetWorkspaceSection.ships,
                OfficialFleetWorkspaceSection.manage,
              },
            );
            expect(
              find.byKey(const Key('official-fleet-members-virtual-list')),
              findsNothing,
            );
            expect(
              find.byKey(const Key('official-fleet-members-rows')),
              findsOneWidget,
            );
            expect(find.byType(OrganizationMemberBoard), findsOneWidget);
            for (final member in members.projection.value.members) {
              expect(
                find.byKey(ValueKey('member-row-${member.memberRef}')),
                findsOneWidget,
              );
              expect(find.text(member.callsign), findsOneWidget);
            }
            expect(communication.chatAvailable, isFalse);
            expect(communication.announcementsAvailable, isFalse);
            final denied = _deniedTabs(t);

            final search = find.byKey(
              const Key('official-fleet-members-search'),
            );
            final field = t.widget<TextField>(search);
            final searchController = field.controller!;
            if (source == 'keyboard') {
              await _tabTo(t, field.focusNode!, observed, activate: false);
            } else {
              await _tap(t, search);
            }
            await t.enterText(search, 'domino_CN');
            if (source == 'keyboard') {
              await _tabTo(
                t,
                _buttonOwner(t, 'official-fleet-members-search-submit'),
                observed,
              );
            } else {
              await _tap(
                t,
                find.byKey(const Key('official-fleet-members-search-submit')),
              );
            }
            await t.pumpAndSettle();
            expect(members.projection.value.query!.search, 'domino_CN');
            expect(
              members.projection.value.query!.sourceRef,
              'officialFleet:7',
            );
            expect(
              members.projection.value.members.single.memberRef,
              'rsi:domino-cn',
            );
            expect(
              find.byKey(const ValueKey('member-row-rsi:domino-cn')),
              findsOneWidget,
            );
            expect(find.text('多米诺'), findsOneWidget);

            if (source == 'keyboard') {
              await _tabTo(t, fixture.focus(t, 'ships'), observed);
              // Immediate local selection policy, not a pixel-playback claim.
              expect(fixture.animating(t), isFalse);
            } else {
              await _tap(t, fixture.tab('ships'));
            }
            await t.pumpAndSettle();
            expect(
              t.widget<OfficialFleetWorkspaceNavigation>(navigation).selected,
              OfficialFleetWorkspaceSection.ships,
            );
            expect(find.byType(CommunityShipsPanel), findsOneWidget);
            expect(find.text('克拉克'), findsOneWidget);
            final shipsPanel = t.widget<CommunityShipsPanel>(
              find.byType(CommunityShipsPanel),
            );
            expect(shipsPanel.port, same(f.sharedShips.adapter));
            expect(
              shipsPanel.targetRef,
              communication.verifiedWorkspaceTargetRef,
            );
            expect(shipsPanel.targetRef, isNotEmpty);
            final shipRead = f.sharedShips.requests.last;
            expect(shipRead.name, 'officialFleet.ships');
            expect(shipRead.payload['sourceRef'], 'officialFleet:7');
            expect(shipRead.payload['targetRef'], shipsPanel.targetRef);
            expect(members.projection.value.query!.search, 'domino_CN');
            if (source == 'keyboard') {
              await _tabTo(
                t,
                _buttonOwner(t, 'official-fleet-open-details'),
                observed,
              );
            } else {
              await _tap(
                t,
                find.byKey(const Key('official-fleet-open-details')),
              );
            }
            await t.pumpAndSettle();
            final dialog = find.byKey(
              const Key('official-fleet-details-dialog'),
            );
            expect(dialog, findsOneWidget);
            expect(find.text("Aster's Wing"), findsWidgets);
            final route =
                ModalRoute.of(t.element(dialog))! as StarBridgeDialogRoute;
            expect(route.isActive, isTrue);
            expect(route.isCurrent, isTrue);
            expect(route.instant, source == 'keyboard');
            if (source == 'keyboard') {
              await _tabTo(
                t,
                _buttonOwner(t, 'official-fleet-details-close'),
                observed,
              );
            } else {
              await _tap(
                t,
                find.byKey(const Key('official-fleet-details-close')),
              );
            }
            await t.pumpAndSettle();
            expect(dialog, findsNothing);

            if (source == 'keyboard') {
              await _tabTo(t, fixture.focus(t, 'members'), observed);
              expect(fixture.animating(t), isFalse);
            } else {
              await _tap(t, fixture.tab('members'));
            }
            await t.pumpAndSettle();
            expect(
              t.widget<OfficialFleetWorkspaceNavigation>(navigation).selected,
              OfficialFleetWorkspaceSection.members,
            );
            expect(
              find.byKey(const Key('official-fleet-members-rows')),
              findsOneWidget,
            );
            expect(
              find.byKey(const ValueKey('member-row-rsi:domino-cn')),
              findsOneWidget,
            );
            expect(
              t.widget<TextField>(search).controller,
              same(searchController),
            );
            expect(searchController.text, 'domino_CN');
            expect(members.projection.value.query!.search, 'domino_CN');
            expect(
              members.projection.value.members.single.memberRef,
              'rsi:domino-cn',
            );
            expect(
              members.projection.value.query!.sourceRef,
              'officialFleet:7',
            );
            expect(module.members, same(members));
            expect(module.ships, same(ships));
            expect(
              t.widget<OfficialFleetPage>(page).sharedShipsPort,
              same(f.sharedShips.adapter),
            );
            expect(f.sharedShips.requests.last, same(shipRead));
            expect(module.communication, same(communication));
            expect(t.widget<OfficialFleetPage>(page).module, same(module));
            expect(module.contextRevision, contextRevision);
            expect(module.projection.value.fleet, same(identity));
            expect(module.projection.value.fleet!.sourceRef, 'officialFleet:7');
            expect(communication.chatAvailable, isFalse);
            expect(communication.announcementsAvailable, isFalse);
            final finalDenied = _deniedTabs(t);
            expect(finalDenied, orderedEquals(denied));
            if (source == 'keyboard') {
              for (final node in denied) {
                expect(observed, isNot(contains(same(node))));
              }
              expect(fixture.animating(t), isFalse);
            }
            expect(
              t
                  .widget<OfficialFleetWorkspaceNavigation>(navigation)
                  .availableSections,
              {
                OfficialFleetWorkspaceSection.members,
                OfficialFleetWorkspaceSection.ships,
                OfficialFleetWorkspaceSection.manage,
              },
            );
            expect(t.takeException(), isNull);
          } finally {
            WidgetController.hitTestWarningShouldBeFatal = originalHitPolicy;
            await t.pumpWidget(const SizedBox.shrink());
            await t.pumpAndSettle();
            semantics.dispose();
          }
        },
        timeout: const Timeout(Duration(seconds: 45)),
      );
    }
  }
}
