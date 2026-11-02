import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/bootstrap/starbridge_app.dart';
import 'package:starbridge_flutter/app/composition/app_composition.dart';
import 'package:starbridge_flutter/app/preferences/app_preferences.dart';
import 'package:starbridge_flutter/app/preferences/in_memory_app_preferences.dart';
import 'package:starbridge_flutter/app/shell/chrome/in_memory_shell_chrome.dart';
import 'package:starbridge_flutter/app/shell/starbridge_shell.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/account/in_memory_account_adapter.dart';
import 'package:starbridge_flutter/features/common/organization_member_board.dart';
import 'package:starbridge_flutter/features/official_fleet/in_memory_official_fleet_adapter.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_models.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_members_models.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_members_port.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_page.dart';
import 'package:starbridge_flutter/platform/window/in_memory_window_chrome.dart';

import '../friends/social_layout_test.dart' show loadFonts;
import '../communities/community_image_test_support.dart'
    show settleCommunityImages;

const _source = 'officialFleet:61';
final _time = DateTime.utc(2026, 10, 16, 20, 30);
final _members = [
  for (var index = 0; index < 3; index++)
    OfficialFleetMember(
      memberRef: '${index + 1}'.padLeft(64, '0'),
      callsign: ['合成舰队队员甲', '合成舰队队员乙', '合成舰队队员丙'][index],
      gameId: 'Fixture_Fleet_${index + 1}',
      officialRankName: ['Officer', 'Member', 'Recruit'][index],
      officialRankValue: [4, 1, 0][index],
      presence: OfficialFleetMemberPresence.unknown,
      server: const OfficialFleetMemberField(
        OfficialFleetMemberFieldState.unknown,
      ),
      ship: const OfficialFleetMemberField(
        OfficialFleetMemberFieldState.unknown,
      ),
      location: const OfficialFleetMemberField(
        OfficialFleetMemberFieldState.unknown,
      ),
      starBridgeConnected: null,
      identityState: OfficialFleetMemberIdentityState.scm,
    ),
];

class _Roster implements OfficialFleetMembersPort {
  int reads = 0;
  @override
  Stream<void> get invalidations => const Stream.empty();
  @override
  Future<OfficialFleetMemberDirectorySnapshot> read(
    OfficialFleetMemberDirectoryQuery query,
  ) async {
    reads++;
    return OfficialFleetMemberDirectorySnapshot.available(
      query: query,
      members: _members,
      totalCount: _members.length,
      onlineCount: null,
      inGameCount: null,
      totalPages: 1,
      coverage: OfficialFleetRosterCoverage.completeOfficialRoster,
      runtimeCapabilities: const OfficialFleetMemberRuntimeCapabilities.none(),
      supportedFilters: const {OfficialFleetMemberFilter.all},
    );
  }

  @override
  Future<void> close() async {}
}

Map<String, double> _rect(Rect value) => {
  'left': value.left,
  'top': value.top,
  'width': value.width,
  'height': value.height,
  'right': value.right,
  'bottom': value.bottom,
};

void main() {
  setUpAll(loadFonts);
  testWidgets(
    'full current fleet shell preserves source identity-rank-only capability',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final roster = _Roster();
      final fleet = OfficialFleetSnapshot.available(
        fleet: const OfficialFleetSummary(
          sourceRef: _source,
          sid: 'FIXTURE071',
          name: '合成主舰队',
          officialRankName: 'Officer',
          officialRankValue: 4,
          profile: OfficialFleetProfileDetails(
            memberCount: 3,
            rsiDescription: '仅用于当前客户端完整主舰队页面截图的合成资料。',
            languageLabels: ['简体中文'],
            primaryFocusLabel: '探索',
          ),
        ),
        freshness: OfficialFleetFreshness.live,
        observedAtUtc: _time,
        profileReadState: OfficialFleetProfileReadState.available,
        profileObservedAtUtc: _time,
        resourceVersion: 1,
      );
      final composition = AppComposition.forTest(
        windowChrome: InMemoryWindowChrome(),
        shellChrome: InMemoryShellChrome(
          initial: InMemoryShellChrome.connectedProjection,
        ),
        accountPort: InMemoryAccountAdapter.forReview(
          AccountReviewState.signedIn,
        ),
        preferences: InMemoryAppPreferences(
          initial: AppPreferences.defaults.copyWith(
            appearanceMode: AppearanceMode.dark,
            interactionStyle: InteractionStyle.standard,
          ),
        ),
        officialFleetPort: InMemoryOfficialFleetAdapter(initial: fleet),
        officialFleetMembersPort: roster,
      );
      final boundaryKey = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundaryKey,
          child: StarBridgeApp(
            composition: composition,
            canPresentIdentityPrompt: () => false,
          ),
        ),
      );
      await settleCommunityImages(tester);
      await tester.tap(find.byKey(const ValueKey('/fleet')));
      await settleCommunityImages(tester);
      await tester.tap(find.byKey(const Key('official-fleet-tab-members')));
      await settleCommunityImages(tester);
      expect(find.byType(StarBridgeShell), findsOneWidget);
      expect(find.byType(OfficialFleetPage), findsOneWidget);
      expect(find.byKey(const Key('official-fleet-workspace')), findsOneWidget);
      expect(find.text('合成主舰队'), findsWidgets);
      final board = tester.widget<OrganizationMemberBoard>(
        find.byType(OrganizationMemberBoard),
      );
      expect(board.columns.keys, ['member', 'role']);
      expect(board.onlineCount, isNull);
      expect(board.inGameCount, isNull);
      expect(board.filters, isEmpty);
      expect(
        find.descendant(
          of: find.byType(OrganizationMemberBoard),
          matching: find.text('服务器'),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: find.byType(OrganizationMemberBoard),
          matching: find.text('未进入游戏'),
        ),
        findsNothing,
      );
      expect(find.byType(OrganizationMemberRow), findsNWidgets(3));
      expect(roster.reads, greaterThan(0));
      expect(tester.takeException(), isNull);
      final directory =
          Platform.environment['ORGANIZATION_071_RUNTIME_CAPTURE_DIR'];
      if (directory != null) {
        final rows = [
          for (final row in tester.widgetList<OrganizationMemberRow>(
            find.byType(OrganizationMemberRow),
          ))
            {
              'memberRef': row.entry.reference,
              'role': row.entry.role,
              'rect': _rect(
                tester.getRect(
                  find.byKey(ValueKey('member-row-${row.entry.reference}')),
                ),
              ),
              'runtimeText': {
                'server': row.entry.server,
                'ship': row.entry.ship,
                'location': row.entry.location,
              },
            },
        ];
        await tester.runAsync(() async {
          final boundary =
              boundaryKey.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
          final image = await boundary.toImage(pixelRatio: 1);
          final bytes = (await image.toByteData(
            format: ui.ImageByteFormat.png,
          ))!.buffer.asUint8List();
          expect(image.width, 1280);
          expect(image.height, 1000);
          image.dispose();
          await Directory(directory).create(recursive: true);
          const file = 'official-fleet-runtime-1280x1000-dark.png';
          await File('$directory/$file').writeAsBytes(bytes);
          final fingerprints = <String, String>{};
          for (final path in [
            'lib/features/official_fleet/official_fleet_page.dart',
            'lib/features/official_fleet/official_fleet_members_section.dart',
            'lib/features/official_fleet/official_fleet_member_views.dart',
            'lib/features/official_fleet/official_fleet_members_models.dart',
            'lib/features/official_fleet/official_fleet_member_runtime_capabilities.dart',
            'lib/features/common/organization_workspace_frame.dart',
            'lib/features/common/organization_member_row.dart',
          ]) {
            fingerprints[path] = sha256
                .convert(await File(path).readAsBytes())
                .toString();
          }
          await File('$directory/official-fleet-full-manifest.json')
              .writeAsString(
                const JsonEncoder.withIndent('  ').convert({
                  'schemaVersion': 1,
                  'synthetic': true,
                  'realAccountAcceptance': false,
                  'fixtureSha256': sha256
                      .convert(
                        await File(
                          'test/features/official_fleet/official_fleet_071_runtime_visual_acceptance_test.dart',
                        ).readAsBytes(),
                      )
                      .toString(),
                  'images': [
                    {
                      'file': file,
                      'width': 1280,
                      'height': 1000,
                      'mode': 'dark',
                      'source': 'current',
                      'sourceRef': _source,
                      'sourceHashes': fingerprints,
                      'sha256': sha256.convert(bytes).toString(),
                      'inputSha256': sha256
                          .convert(
                            utf8.encode(
                              jsonEncode({
                                'fleetName': '合成主舰队',
                                'source': _source,
                                'observedAtUtc': _time.toIso8601String(),
                                'members': _members
                                    .map(
                                      (member) => {
                                        'reference': member.memberRef,
                                        'callsign': member.callsign,
                                        'gameId': member.gameId,
                                        'rank': member.officialRankName,
                                        'rankValue': member.officialRankValue,
                                      },
                                    )
                                    .toList(),
                                'runtimeCapabilities': 'none',
                              }),
                            ),
                          )
                          .toString(),
                      'nativeViewport': true,
                      'viewportExpanded': false,
                      'croppedOrStitched': false,
                      'devicePixelRatio': 1,
                      'textScale': 1,
                      'visibleColumns': board.columns.keys,
                      'runtimeCapabilities': 'none; current production-source identity and official rank only',
                      'workspaceRect': _rect(
                        tester.getRect(
                          find.byKey(const Key('official-fleet-workspace')),
                        ),
                      ),
                      'members': rows,
                    },
                  ],
                  'visibleClientLaunched': false,
                  'accountOperations': false,
                }),
              );
        });
      }
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    },
  );
}
